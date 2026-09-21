"""Ordered class and resource sources for the BendJVM host.

The host deliberately supplies bytes and origins only; class-file interpretation and
class dependency discovery remain in Bend.  ``Classpath`` expands local manifest
``Class-Path`` entries eagerly, and therefore owns its source handles for the life
of the context manager.  There is no persistent/lazy archive-handle layer: callers
must close a classpath (or use it as a context manager) before it is discarded.
"""

from __future__ import annotations

from dataclasses import dataclass
import io
from pathlib import Path, PurePosixPath, PureWindowsPath
import stat
import urllib.parse
import zipfile
from typing import Iterable, Iterator


DEFAULT_MAX_ENTRY_BYTES = 64 * 1024 * 1024
DEFAULT_MAX_TOTAL_BYTES = 512 * 1024 * 1024


class ClasspathError(Exception):
    """An actionable classpath, archive, or manifest failure."""


@dataclass(frozen=True)
class SourceMatch:
    """Bytes selected from one source, retaining their physical origin."""

    name: str
    data: bytes
    origin: str
    source: "Source"

    @property
    def bytes(self) -> bytes:
        return self.data


class EntryStream(io.RawIOBase):
    """A bounded, closeable stream over one archive entry."""

    def __init__(self, owner: "ArchiveSource", info: zipfile.ZipInfo, request: str):
        super().__init__()
        self._owner = owner
        self._info = info
        self._request = request
        self._entry_read = 0
        self._closed = False
        try:
            self._stream = owner._zip.open(info, "r")  # type: ignore[union-attr]
        except Exception as error:
            raise owner._error(request, f"cannot open archive entry: {error}") from error

    @property
    def origin(self) -> str:
        return self._owner.entry_origin(self._info.filename)

    def readable(self) -> bool:
        return not self._closed

    def read(self, size: int = -1) -> bytes:
        if self._closed:
            raise ValueError("I/O operation on closed archive entry")
        if size is not None and size < -1:
            raise ValueError("negative read size")
        try:
            if size == 0:
                return b""
            if size is None or size < 0:
                chunks: list[bytes] = []
                while True:
                    chunk = self._read_chunk(64 * 1024)
                    if not chunk:
                        break
                    chunks.append(chunk)
                return b"".join(chunks)
            return self._read_chunk(size)
        except ClasspathError:
            self.close()
            raise
        except Exception as error:
            self.close()
            raise self._owner._error(self._request, f"cannot read archive entry: {error}") from error

    def _read_chunk(self, size: int) -> bytes:
        if size == 0:
            return b""
        # Never let a caller's large read request turn into an unbounded
        # decompression allocation. One extra byte detects either limit being
        # crossed without relying on ZIP metadata.
        remaining_entry = self._owner.max_entry_bytes - self._entry_read + 1
        remaining_total = self._owner.max_total_bytes - self._owner._total_read + 1
        request_size = min(size, 64 * 1024, remaining_entry, remaining_total)
        chunk = self._stream.read(max(1, request_size))
        count = len(chunk)
        next_entry = self._entry_read + count
        if next_entry > self._owner.max_entry_bytes:
            raise self._owner._error(
                self._request,
                f"entry decompressed size exceeds limit {self._owner.max_entry_bytes}",
            )
        next_total = self._owner._total_read + count
        if next_total > self._owner.max_total_bytes:
            raise self._owner._error(
                self._request,
                f"archive decompressed size exceeds total limit {self._owner.max_total_bytes}",
            )
        self._entry_read = next_entry
        self._owner._total_read = next_total
        return chunk

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            try:
                self._stream.close()
            finally:
                super().close()

    def __enter__(self) -> "EntryStream":
        if self._closed:
            raise ValueError("I/O operation on closed archive entry")
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()


class Source:
    """Common ordered source interface."""

    origin: str
    key: str

    def find_class(self, binary_name: str) -> SourceMatch | None:
        path = class_path(binary_name)
        return self.find_resource(path)

    def find_resource(self, name: str) -> SourceMatch | None:
        raise NotImplementedError

    def read_class(self, binary_name: str) -> SourceMatch | None:
        return self.find_class(binary_name)

    def read_resource(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)
    def lookup_class(self, binary_name: str) -> SourceMatch | None:
        return self.find_class(binary_name)

    def lookup_resource(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)

    def lookup(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)


    def close(self) -> None:
        pass

    def __enter__(self) -> "Source":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()


class MissingSource(Source):
    """A missing classpath entry, intentionally non-matching."""

    def __init__(self, path: Path):
        self.path = path
        self.origin = str(path)
        self.key = _canonical(path)

    def find_resource(self, name: str) -> SourceMatch | None:
        _safe_name(name, self.origin)
        return None


class DirectorySource(Source):
    """A classpath root backed by a directory."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.origin = str(self.path)
        self.key = _canonical(self.path)
        path_info = _path_stat(self.path, self.origin)
        if path_info is not None and not stat.S_ISDIR(path_info.st_mode):
            raise ClasspathError(f"{self.origin}: classpath source is not a directory")

    def find_resource(self, name: str) -> SourceMatch | None:
        _safe_name(name, self.origin)
        candidate = self.path.joinpath(*name.split("/"))
        try:
            if not candidate.is_file():
                return None
            data = candidate.read_bytes()
        except OSError as error:
            raise ClasspathError(
                f"{self.origin}: cannot read resource {name!r}: {error}"
            ) from error
        return SourceMatch(name, data, str(candidate), self)


class ArchiveSource(Source):
    """A bounded local JAR/ZIP source indexed without extracting files."""

    def __init__(
        self,
        path: str | Path,
        *,
        max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES,
        max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES,
    ):
        self.path = Path(path)
        self.origin = str(self.path)
        self.key = _canonical(self.path)
        if max_entry_bytes < 0 or max_total_bytes < 0:
            raise ValueError("archive byte limits must be non-negative")
        self.max_entry_bytes = max_entry_bytes
        self.max_total_bytes = max_total_bytes
        self._total_read = 0
        self._closed = False
        self._zip: zipfile.ZipFile | None = None
        self._entries: dict[str, zipfile.ZipInfo] = {}
        path_info = _path_stat(self.path, self.origin)
        if path_info is None:
            return
        if not stat.S_ISREG(path_info.st_mode):
            raise ClasspathError(f"{self.origin}: archive source is not a regular file")
        try:
            self._zip = zipfile.ZipFile(self.path, "r")
            for info in self._zip.infolist():
                self._validate_info(info)
                if info.filename in self._entries:
                    raise self._error(info.filename, "duplicate archive entry name")
                self._entries[info.filename] = info
        except ClasspathError:
            self.close()
            raise
        except (OSError, zipfile.BadZipFile, RuntimeError, ValueError) as error:
            self.close()
            raise ClasspathError(f"{self.origin}: cannot index archive: {error}") from error

    def _validate_info(self, info: zipfile.ZipInfo) -> None:
        _safe_name(info.filename, self.origin)
        if info.flag_bits & 0x1:
            raise self._error(info.filename, "encrypted archive entries are unsupported")
        if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise self._error(
                info.filename,
                f"unsupported compression method {info.compress_type}",
            )

    def _error(self, request: str, message: str) -> ClasspathError:
        return ClasspathError(f"{self.origin}!/{request}: {message}")

    def entry_origin(self, name: str) -> str:
        return f"{self.origin}!/{name}"

    def _lookup(self, name: str) -> zipfile.ZipInfo | None:
        _safe_name(name, self.origin)
        if self._closed or self._zip is None:
            return None
        return self._entries.get(name)

    def open_entry(self, name: str, *, request: str | None = None) -> EntryStream | None:
        info = self._lookup(name)
        if info is None:
            return None
        return EntryStream(self, info, request or name)

    def read_entry(self, name: str, *, request: str | None = None) -> bytes | None:
        stream = self.open_entry(name, request=request)
        if stream is None:
            return None
        with stream:
            return stream.read()

    def find_resource(self, name: str) -> SourceMatch | None:
        data = self.read_entry(name)
        if data is None:
            return None
        return SourceMatch(name, data, self.entry_origin(name), self)

    def manifest_attributes(self) -> dict[str, str]:
        if "META-INF/MANIFEST.MF" not in self._entries:
            return {}
        data = self.read_entry("META-INF/MANIFEST.MF", request="manifest META-INF/MANIFEST.MF")
        assert data is not None
        return parse_manifest(data, origin=self.entry_origin("META-INF/MANIFEST.MF"))

    def manifest_class_path(self) -> tuple[str, ...]:
        value = self.manifest_attributes().get("class-path", "")
        return tuple(value.split()) if value else ()

    def manifest_source(self, token: str) -> Source:
        decoded = urllib.parse.unquote(token)
        parsed = urllib.parse.urlsplit(decoded)
        if parsed.scheme and parsed.scheme.lower() != "file":
            raise self._error(token, f"remote or unsupported manifest URL scheme {parsed.scheme!r}")
        if parsed.scheme.lower() == "file":
            if parsed.netloc and parsed.netloc.lower() != "localhost":
                raise self._error(token, "remote file URL host is unsupported")
            if parsed.query or parsed.fragment:
                raise self._error(token, "manifest file URL query/fragment is unsupported")
            target = Path(urllib.parse.unquote(parsed.path))
            if not target.is_absolute():
                target = self.path.parent / target
        else:
            if parsed.query or parsed.fragment:
                raise self._error(token, "manifest path query/fragment is unsupported")
            target = Path(urllib.parse.unquote(parsed.path))
            if not target.is_absolute():
                target = self.path.parent / target
        if target.exists() and target.is_dir():
            return DirectorySource(target)
        if target.exists() and target.is_file():
            return ArchiveSource(
                target,
                max_entry_bytes=self.max_entry_bytes,
                max_total_bytes=self.max_total_bytes,
            )
        if target.suffix.lower() in (".jar", ".zip"):
            return ArchiveSource(
                target,
                max_entry_bytes=self.max_entry_bytes,
                max_total_bytes=self.max_total_bytes,
            )
        return MissingSource(target)

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            if self._zip is not None:
                self._zip.close()
                self._zip = None

    def __del__(self):  # pragma: no cover - best effort only
        try:
            self.close()
        except Exception:
            pass


@dataclass(frozen=True)
class Classpath:
    """Left-to-right class and resource lookup over ordered sources."""

    sources: tuple[Source, ...]

    def __init__(
        self,
        sources: Iterable[Source | str | Path],
        *,
        expand_manifests: bool = True,
        max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES,
        max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES,
    ):
        created: list[Source] = []
        try:
            initial = tuple(
                source
                if isinstance(source, Source)
                else source_from_path(
                    source,
                    max_entry_bytes=max_entry_bytes,
                    max_total_bytes=max_total_bytes,
                )
                for source in sources
            )
            created.extend(initial)
            object.__setattr__(
                self,
                "sources",
                _expand_sources(
                    initial,
                    expand_manifests=expand_manifests,
                    max_entry_bytes=max_entry_bytes,
                    max_total_bytes=max_total_bytes,
                ),
            )
        except Exception:
            for source in created:
                source.close()
            raise

    def __iter__(self) -> Iterator[Source]:
        return iter(self.sources)

    def find_class(self, binary_name: str) -> SourceMatch | None:
        path = class_path(binary_name)
        for source in self.sources:
            found = source.find_resource(path)
            if found is not None:
                return found
        return None

    def find_resource(self, name: str) -> SourceMatch | None:
        _safe_name(name, "classpath")
        for source in self.sources:
            found = source.find_resource(name)
            if found is not None:
                return found
        return None

    def read_class(self, binary_name: str) -> SourceMatch | None:
        return self.find_class(binary_name)

    def lookup_class(self, binary_name: str) -> SourceMatch | None:
        return self.find_class(binary_name)

    def lookup_resource(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)

    def lookup(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)

    def read_resource(self, name: str) -> SourceMatch | None:
        return self.find_resource(name)

    def open_resource(self, name: str) -> EntryStream | io.BytesIO | None:
        _safe_name(name, "classpath")
        for source in self.sources:
            if isinstance(source, ArchiveSource):
                stream = source.open_entry(name)
                if stream is not None:
                    return stream
            else:
                found = source.find_resource(name)
                if found is not None:
                    return io.BytesIO(found.data)
        return None

    def close(self) -> None:
        for source in self.sources:
            source.close()

    def __enter__(self) -> "Classpath":
        return self

    def __exit__(self, exc_type, exc_value, traceback) -> None:
        self.close()

    @classmethod
    def from_paths(cls, paths: Iterable[str | Path], **kwargs) -> "Classpath":
        return cls(paths, **kwargs)

    @classmethod
    def expand(cls, paths: Iterable[str | Path], **kwargs) -> "Classpath":
        return cls.from_paths(paths, **kwargs)


# Descriptive aliases make the source boundary convenient for callers without
# creating separate implementations.
JarSource = ArchiveSource
ZipSource = ArchiveSource
DirectoryRoot = DirectorySource
ClassPath = Classpath
ArchiveRoot = ArchiveSource


def _canonical(path: Path) -> str:
    try:
        return str(path.resolve(strict=False))
    except OSError:
        return str(path.absolute())
def _path_stat(path: Path, origin: str):
    try:
        return path.stat()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise ClasspathError(f"{origin}: cannot inspect classpath source: {error}") from error



def _safe_name(name: str, origin: str) -> None:
    if not isinstance(name, str) or not name:
        raise ClasspathError(f"{origin}: invalid empty lookup name")
    if "\\" in name or "\x00" in name:
        raise ClasspathError(f"{origin}: unsafe lookup name {name!r}")
    if name.startswith("/") or PurePosixPath(name).is_absolute():
        raise ClasspathError(f"{origin}: unsafe absolute lookup name {name!r}")
    windows = PureWindowsPath(name)
    if windows.is_absolute() or windows.drive:
        raise ClasspathError(f"{origin}: unsafe lookup name {name!r}")
    parts = name.split("/")
    if any(part in (".", "..") for part in parts):
        raise ClasspathError(f"{origin}: unsafe traversal lookup name {name!r}")
    if any(part == "" for part in parts[:-1]):
        raise ClasspathError(f"{origin}: unsafe empty path component {name!r}")


def class_path(binary_name: str) -> str:
    if not isinstance(binary_name, str) or not binary_name:
        raise ClasspathError("classpath: invalid empty binary class name")
    if binary_name.endswith(".class"):
        stem = binary_name[:-6]
        path = (stem if "/" in stem else stem.replace(".", "/")) + ".class"
    elif "/" in binary_name:
        path = binary_name + ".class"
    else:
        path = binary_name.replace(".", "/") + ".class"
    _safe_name(path, "classpath")
    return path


def source_from_path(
    path: str | Path,
    *,
    max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES,
    max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES,
) -> Source:
    candidate = Path(path)
    path_info = _path_stat(candidate, str(candidate))
    if path_info is not None and stat.S_ISDIR(path_info.st_mode):
        return DirectorySource(candidate)
    if path_info is not None and stat.S_ISREG(path_info.st_mode):
        return ArchiveSource(
            candidate,
            max_entry_bytes=max_entry_bytes,
            max_total_bytes=max_total_bytes,
        )
    if candidate.suffix.lower() in (".jar", ".zip"):
        return ArchiveSource(
            candidate,
            max_entry_bytes=max_entry_bytes,
            max_total_bytes=max_total_bytes,
        )
    return MissingSource(candidate)


def parse_manifest(data: bytes, *, origin: str = "manifest") -> dict[str, str]:
    """Parse only the manifest main section, with case-insensitive attributes."""

    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ClasspathError(f"{origin}: manifest is not valid UTF-8: {error}") from error
    lines = text.splitlines()
    attrs: dict[str, str] = {}
    current: str | None = None
    for line in lines:
        if line == "":
            break
        if line.startswith(" "):
            if current is None:
                raise ClasspathError(f"{origin}: continuation without an attribute")
            attrs[current] += line[1:]
            continue
        if ":" not in line:
            raise ClasspathError(f"{origin}: malformed manifest attribute line {line!r}")
        name, value = line.split(":", 1)
        if not name or value[:1] not in ("", " "):
            raise ClasspathError(f"{origin}: malformed manifest attribute line {line!r}")
        key = name.casefold()
        if key in attrs:
            raise ClasspathError(f"{origin}: duplicate main attribute {name!r}")
        attrs[key] = value[1:] if value.startswith(" ") else value
        current = key
    return attrs


def _expand_sources(
    initial: tuple[Source, ...],
    *,
    expand_manifests: bool,
    max_entry_bytes: int,
    max_total_bytes: int,
) -> tuple[Source, ...]:
    result: list[Source] = []
    seen: set[str] = set()

    def visit(source: Source) -> None:
        if source.key in seen:
            if not any(source is existing for existing in result):
                source.close()
            return
        seen.add(source.key)
        result.append(source)
        if not expand_manifests or not isinstance(source, ArchiveSource):
            return
        for token in source.manifest_class_path():
            child = source.manifest_source(token)
            if not isinstance(child, (ArchiveSource, DirectorySource, MissingSource)):
                continue
            visit(child)

    try:
        for source in initial:
            visit(source)
    except Exception:
        for source in result:
            source.close()
        raise
    return tuple(result)

def expand_classpath(
    paths: Iterable[str | Path],
    *,
    max_entry_bytes: int = DEFAULT_MAX_ENTRY_BYTES,
    max_total_bytes: int = DEFAULT_MAX_TOTAL_BYTES,
) -> Classpath:
    return Classpath.from_paths(
        paths,
        max_entry_bytes=max_entry_bytes,
        max_total_bytes=max_total_bytes,
    )


__all__ = [
    "ArchiveRoot", "ArchiveSource", "ClassPath", "Classpath", "ClasspathError",
    "DEFAULT_MAX_ENTRY_BYTES", "DEFAULT_MAX_TOTAL_BYTES", "DirectoryRoot",
    "DirectorySource", "EntryStream", "JarSource", "MissingSource",
    "Source", "SourceMatch", "ZipSource", "class_path", "expand_classpath",
    "parse_manifest", "source_from_path",
]
