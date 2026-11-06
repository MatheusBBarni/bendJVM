public class WideSwitchFixture {
    static long longField;
    static double doubleField;
    static long[] longArray;
    static double[] doubleArray;
    static final long WIDE_CONSTANT = 0x1234567887654321L;
    static final double DOUBLE_CONSTANT = 0x1.123456789abcdp+5;

    static class WideHolder {
        Object object;
        long value;
        double decimal;
        WideHolder() { }
        WideHolder(long value) { this.value = value; }
    }
    interface WideCallback {
        long combine(long base, double adjustment);
    }

    @WideMetadata
    static class WideAnnotated { }



    static Object assignReference(WideHolder holder, Object value) {
        return holder.object = value;
    }

    static int assignInt(int[] values, int value) {
        return values[0] = value;
    }

    static long assignStatic(long value) {
        return longField = value;
    }

    static long assignField(WideHolder holder, long value) {
        return holder.value = value;
    }

    static long assignArray(long[] values, long value) {
        return values[0] = value;
    }

    public static long addWide(long base, double adjustment) {
        return base + (long) adjustment;
    }



    static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    static void expectLongParseFailure(String value) {
        try {
            Long.parseLong(value);
            throw new AssertionError("accepted invalid long");
        } catch (NumberFormatException expected) { }
    }
    static boolean longDivideByZeroThrows() {
        long numerator = 1L;
        long zero = 0L;
        try {
            return numerator / zero == 0L;
        } catch (ArithmeticException expected) {
            return true;
        }
    }



    static int dense(int key) {
        switch (key) {
            case -2: return 20;
            case -1: return 10;
            case 0: return 0;
            case 1: return 11;
            case 2: return 22;
            default: return -99;
        }
    }

    static int sparse(int key) {
        switch (key) {
            case -1000: return 1;
            case -7: return 2;
            case 42: return 3;
            case 10000: return 4;
            default: return -1;
        }
    }
    static long wideLocals() {
        int v0 = 0, v1 = 1, v2 = 2, v3 = 3, v4 = 4, v5 = 5, v6 = 6, v7 = 7, v8 = 8, v9 = 9;
        int v10 = 10, v11 = 11, v12 = 12, v13 = 13, v14 = 14, v15 = 15, v16 = 16, v17 = 17, v18 = 18, v19 = 19;
        int v20 = 20, v21 = 21, v22 = 22, v23 = 23, v24 = 24, v25 = 25, v26 = 26, v27 = 27, v28 = 28, v29 = 29;
        int v30 = 30, v31 = 31, v32 = 32, v33 = 33, v34 = 34, v35 = 35, v36 = 36, v37 = 37, v38 = 38, v39 = 39;
        int v40 = 40, v41 = 41, v42 = 42, v43 = 43, v44 = 44, v45 = 45, v46 = 46, v47 = 47, v48 = 48, v49 = 49;
        int v50 = 50, v51 = 51, v52 = 52, v53 = 53, v54 = 54, v55 = 55, v56 = 56, v57 = 57, v58 = 58, v59 = 59;
        int v60 = 60, v61 = 61, v62 = 62, v63 = 63, v64 = 64, v65 = 65, v66 = 66, v67 = 67, v68 = 68, v69 = 69;
        int v70 = 70, v71 = 71, v72 = 72, v73 = 73, v74 = 74, v75 = 75, v76 = 76, v77 = 77, v78 = 78, v79 = 79;
        int v80 = 80, v81 = 81, v82 = 82, v83 = 83, v84 = 84, v85 = 85, v86 = 86, v87 = 87, v88 = 88, v89 = 89;
        int v90 = 90, v91 = 91, v92 = 92, v93 = 93, v94 = 94, v95 = 95, v96 = 96, v97 = 97, v98 = 98, v99 = 99;
        int v100 = 100, v101 = 101, v102 = 102, v103 = 103, v104 = 104, v105 = 105, v106 = 106, v107 = 107, v108 = 108, v109 = 109;
        int v110 = 110, v111 = 111, v112 = 112, v113 = 113, v114 = 114, v115 = 115, v116 = 116, v117 = 117, v118 = 118, v119 = 119;
        int v120 = 120, v121 = 121, v122 = 122, v123 = 123, v124 = 124, v125 = 125, v126 = 126, v127 = 127, v128 = 128, v129 = 129;
        int v130 = 130, v131 = 131, v132 = 132, v133 = 133, v134 = 134, v135 = 135, v136 = 136, v137 = 137, v138 = 138, v139 = 139;
        int v140 = 140, v141 = 141, v142 = 142, v143 = 143, v144 = 144, v145 = 145, v146 = 146, v147 = 147, v148 = 148, v149 = 149;
        int v150 = 150, v151 = 151, v152 = 152, v153 = 153, v154 = 154, v155 = 155, v156 = 156, v157 = 157, v158 = 158, v159 = 159;
        int v160 = 160, v161 = 161, v162 = 162, v163 = 163, v164 = 164, v165 = 165, v166 = 166, v167 = 167, v168 = 168, v169 = 169;
        int v170 = 170, v171 = 171, v172 = 172, v173 = 173, v174 = 174, v175 = 175, v176 = 176, v177 = 177, v178 = 178, v179 = 179;
        int v180 = 180, v181 = 181, v182 = 182, v183 = 183, v184 = 184, v185 = 185, v186 = 186, v187 = 187, v188 = 188, v189 = 189;
        int v190 = 190, v191 = 191, v192 = 192, v193 = 193, v194 = 194, v195 = 195, v196 = 196, v197 = 197, v198 = 198, v199 = 199;
        int v200 = 200, v201 = 201, v202 = 202, v203 = 203, v204 = 204, v205 = 205, v206 = 206, v207 = 207, v208 = 208, v209 = 209;
        int v210 = 210, v211 = 211, v212 = 212, v213 = 213, v214 = 214, v215 = 215, v216 = 216, v217 = 217, v218 = 218, v219 = 219;
        int v220 = 220, v221 = 221, v222 = 222, v223 = 223, v224 = 224, v225 = 225, v226 = 226, v227 = 227, v228 = 228, v229 = 229;
        int v230 = 230, v231 = 231, v232 = 232, v233 = 233, v234 = 234, v235 = 235, v236 = 236, v237 = 237, v238 = 238, v239 = 239;
        int v240 = 240, v241 = 241, v242 = 242, v243 = 243, v244 = 244, v245 = 245, v246 = 246, v247 = 247, v248 = 248, v249 = 249;
        int v250 = 250, v251 = 251, v252 = 252, v253 = 253, v254 = 254, v255 = 255, v256 = 256, v257 = 257, v258 = 258, v259 = 259;
        v259++;
        long wideValue = 0x1234567887654321L;
        float wideFloat = 1.25f;
        Object wideObject = "wide";
        double wideDouble = 2.5d;
        wideFloat += 1.0f;
        wideObject = wideObject;
        wideDouble += 1.0d;
        return wideValue + v259 + (long) wideFloat + (wideObject != null ? 1 : 0) + (long) wideDouble;
    }


    static void randomizedLongArithmetic() {
        long state = 0x123456789abcdef0L;
        for (int i = 0; i < 6; i++) {
            state = state * 0x5851f42d4c957f2dL + 0x14057b7ef767814fL;
            long right = state ^ 0x7fedcba987654321L;
            if (right == 0L) right = 1L;
            System.out.println(state);
            System.out.println(state + right);
            System.out.println(state * right);
            System.out.println(state / right);
            System.out.println(state % right);
        }
    }

    static strictfp void randomizedDoubleArithmetic() {
        long state = 0x123456789abcdef0L;
        for (int i = 0; i < 6; i++) {
            state = state * 0x5851f42d4c957f2dL + 0x14057b7ef767814fL;
            double left = Double.longBitsToDouble(state);
            state = state * 0x5851f42d4c957f2dL + 0x14057b7ef767814fL;
            double right = Double.longBitsToDouble(state);
            System.out.println(left);
            System.out.println(right);
            System.out.println(Double.doubleToLongBits(left + right));
            System.out.println(Double.doubleToLongBits(left - right));
            System.out.println(Double.doubleToLongBits(left * right));
            System.out.println(Double.doubleToLongBits(left / right));
            System.out.println(Double.doubleToLongBits(left % right));
        }
    }

    public static void main(String[] args) {
        WideHolder holder = new WideHolder();
        Object assigned = new Object();
        check(assignReference(holder, assigned) == assigned && holder.object == assigned,
              "reference dup_x1");
        int[] assignedInts = new int[1];
        check(assignInt(assignedInts, 73) == 73 && assignedInts[0] == 73,
              "integer dup_x2");
        long assignedStatic = assignStatic(0x1234567887654321L);
        check(assignedStatic == 0x1234567887654321L, "long dup2");
        long assignedField = assignField(holder, 0x2345678998765432L);
        check(assignedField == 0x2345678998765432L &&
              holder.value == 0x2345678998765432L, "long dup2_x1");
        long[] assignedLongs = new long[1];
        check(assignArray(assignedLongs, 0x3456789a98765432L) ==
              0x3456789a98765432L && assignedLongs[0] == 0x3456789a98765432L,
              "long dup2_x2");
        long max = Long.MAX_VALUE;
        long min = Long.MIN_VALUE;
        long carry = max + 1L;
        long borrow = min - 1L;
        long multiplicand = 0x12345678L;
        long multiplier = 0x100000001L;
        long product = multiplicand * multiplier;
        System.out.println(carry);
        System.out.println(borrow);
        System.out.println(product);
        check(carry == min && borrow == max, "long wrap/carry");
        check(product == 0x1234567812345678L, "long multiply words");

        System.out.println(min < -1L);
        System.out.println(max > 0L);
        System.out.println(min / -1L);
        System.out.println(min % -1L);
        System.out.println(-7L / 3L);
        System.out.println(-7L % 3L);
        check(min / -1L == min && min % -1L == 0L, "long MIN/-1");
        check(-7L / 3L == -2L && -7L % 3L == -1L, "signed long div/rem");
        check(longDivideByZeroThrows(), "long division by zero");

        long shiftSource = 1L;
        int shiftDistance = 65;
        long shiftedLeft = shiftSource << shiftDistance;
        long shiftedRight = -8L >> shiftDistance;
        long allOnes = -1L;
        int negativeDistance = -1;
        long shiftedUnsigned = allOnes >>> negativeDistance;
        long bitsLeft = 0x55aaL;
        long bitsRight = 0x0ff0L;
        System.out.println(shiftedLeft);
        System.out.println(shiftedRight);
        System.out.println(shiftedUnsigned);
        System.out.println(bitsLeft & bitsRight);
        System.out.println(bitsLeft | bitsRight);
        System.out.println(bitsLeft ^ bitsRight);
        check(shiftedLeft == 2L && shiftedRight == -4L && shiftedUnsigned == 1L,
              "masked long shifts");
        check((1L << 31) == 2147483648L && (1L << 32) == 4294967296L &&
              (1L << 63) == Long.MIN_VALUE,
              "long shift word boundaries");
        check((0x55aaL & 0x0ff0L) == 0x05a0L, "long bitwise and");

        int intSource = 0xabcdef01;
        long longSource = 0x12345678abcdef01L;
        int narrowed = (int) longSource;
        long widened = (long) intSource;
        System.out.println(narrowed);
        System.out.println(widened);
        check(narrowed == 0xabcdef01 && widened == -1412567295L, "i2l/l2i");

        longField = 0x1234567887654321L;
        doubleField = -13.25;
        long[] sourceLongs = { longField, min, max };
        longArray = new long[4];
        System.arraycopy(sourceLongs, 0, longArray, 1, 3);
        double[] sourceDoubles = { doubleField, -0.0, Double.MIN_VALUE };
        doubleArray = new double[4];
        System.arraycopy(sourceDoubles, 0, doubleArray, 1, 3);
        System.out.println(longField);
        System.out.println(longArray[1]);
        System.out.println(longArray[2]);
        System.out.println(longArray[3]);
        System.out.println(doubleField);
        System.out.println(doubleArray[1]);
        System.out.println(Double.doubleToRawLongBits(doubleArray[2]));
        System.out.println(Double.doubleToRawLongBits(doubleArray[3]));
        check(longArray[1] == longField && longArray[2] == min && longArray[3] == max,
              "long field/arraycopy");
        check(Double.doubleToRawLongBits(doubleArray[2]) == 0x8000000000000000L,
              "double signed zero arraycopy");
        check(Double.doubleToRawLongBits(doubleArray[3]) == 1L, "double subnormal arraycopy");

        try {
            java.lang.reflect.Field constantLong = WideSwitchFixture.class.getDeclaredField("WIDE_CONSTANT");
            java.lang.reflect.Field constantDouble = WideSwitchFixture.class.getDeclaredField("DOUBLE_CONSTANT");
            constantLong.setAccessible(true);
            constantDouble.setAccessible(true);
            System.out.println(constantLong.getLong(null));
            System.out.println(Double.doubleToRawLongBits(constantDouble.getDouble(null)));
        } catch (Exception failure) {
            throw new AssertionError("wide ConstantValue reflection");
        }

        Long cachedLow = Long.valueOf(-128L);
        Long cachedHigh = Long.valueOf(127L);
        Long alsoLow = Long.valueOf(-128L);
        Long alsoHigh = Long.valueOf(127L);
        Long outside = Long.valueOf(128L);
        System.out.println(cachedLow == alsoLow);
        System.out.println(cachedHigh == alsoHigh);
        System.out.println(outside.longValue());
        check(cachedLow == alsoLow && cachedHigh == alsoHigh, "Long mandatory cache");
        check(outside.longValue() == 128L, "Long outside-cache value");

        long negativeZeroBits = 0x8000000000000000L;
        long subnormalBits = 1L;
        long nanBits = 0x7ff8000000000042L;
        double negativeZero = Double.longBitsToDouble(negativeZeroBits);
        double subnormal = Double.longBitsToDouble(subnormalBits);
        double nan = Double.longBitsToDouble(nanBits);
        double infinity = Double.longBitsToDouble(0x7ff0000000000000L);
        System.out.println(Double.doubleToRawLongBits(negativeZero));
        System.out.println(Double.doubleToRawLongBits(subnormal));
        System.out.println(Double.doubleToRawLongBits(nan));
        System.out.println(Double.doubleToRawLongBits(infinity));
        check(Double.doubleToRawLongBits(negativeZero) == negativeZeroBits, "negative zero bits");
        check(Double.doubleToRawLongBits(subnormal) == subnormalBits, "subnormal bits");
        check(Double.doubleToRawLongBits(nan) == nanBits, "NaN payload bits");
        check(Double.doubleToRawLongBits(infinity) == 0x7ff0000000000000L, "infinity bits");

        double largestSubnormal = Double.longBitsToDouble(0x000fffffffffffffL);
        double smallestNormal = Double.longBitsToDouble(0x0010000000000000L);
        double largestFinite = Double.longBitsToDouble(0x7fefffffffffffffL);
        System.out.println(negativeZero);
        System.out.println(subnormal);
        System.out.println(largestSubnormal);
        System.out.println(smallestNormal);
        System.out.println(largestFinite);
        System.out.println(0.001);
        System.out.println(0.0001);
        System.out.println(9999999.0);
        System.out.println(10000000.0);
        System.out.println(1.2345678901234567);
        System.out.println(String.valueOf(subnormal));
        System.out.println(new StringBuilder().append(largestFinite));

        double first = 1.5;
        double second = 2.25;
        double third = 2.5;
        double dividend = 7.5;
        double divisor = 2.0;
        double negativeDividend = -7.5;
        double sum = first + second;
        double difference = first - second;
        double multiplication = first * third;
        double division = dividend / divisor;
        double remainder = negativeDividend % divisor;
        double zero = 0.0;
        double positiveInfinity = 1.0 / zero;
        double negativeInfinity = 1.0 / negativeZero;
        System.out.println(sum);
        System.out.println(difference);
        System.out.println(multiplication);
        System.out.println(division);
        System.out.println(remainder);
        System.out.println(positiveInfinity);
        System.out.println(negativeInfinity);
        System.out.println(subnormal == 0.0);
        System.out.println(nan != nan);
        check(sum == 3.75 && difference == -0.75 && multiplication == 3.75,
              "double add/sub/mul");
        check(division == 3.75 && remainder == -1.5, "double div/rem");
        check(positiveInfinity == infinity && negativeInfinity == Double.NEGATIVE_INFINITY,
              "double exceptional division");
        check(subnormal != 0.0 && nan != nan, "double subnormal/NaN comparisons");
        double minSubnormal = Double.longBitsToDouble(1L);
        double halfSubnormal = minSubnormal / 2.0d;
        double doubledSubnormal = minSubnormal + minSubnormal;
        double largestPlusLargest = largestFinite + largestFinite;
        double positiveZeroValue = 0.0d;
        double negativeZeroValue = -positiveZeroValue;
        double doubleNegatedZero = -negativeZeroValue;
        double negativeZeroSum = negativeZeroValue + negativeZeroValue;
        double mixedZeroSum = negativeZeroValue + positiveZeroValue;
        System.out.println(Double.doubleToRawLongBits(halfSubnormal));
        System.out.println(Double.doubleToRawLongBits(doubledSubnormal));
        System.out.println(Double.doubleToRawLongBits(largestPlusLargest));
        System.out.println(Double.doubleToRawLongBits(negativeZeroValue));
        System.out.println(Double.doubleToRawLongBits(doubleNegatedZero));
        System.out.println(Double.doubleToRawLongBits(negativeZeroSum));
        System.out.println(Double.doubleToRawLongBits(mixedZeroSum));
        check(Double.doubleToRawLongBits(halfSubnormal) == 0L &&
              Double.doubleToRawLongBits(doubledSubnormal) == 2L &&
              Double.isInfinite(largestPlusLargest),
              "subnormal and overflow arithmetic");
        check(Double.doubleToRawLongBits(negativeZeroValue) == Long.MIN_VALUE &&
              Double.doubleToRawLongBits(doubleNegatedZero) == 0L &&
              Double.doubleToRawLongBits(negativeZeroSum) == Long.MIN_VALUE &&
              Double.doubleToRawLongBits(mixedZeroSum) == 0L,
              "signed-zero arithmetic");

        double tiesEvenDown = 1.0d + 0x1.0p-53;
        double tiesEvenUp = 1.0d + 0x1.8p-52;
        check(Double.doubleToRawLongBits(tiesEvenDown) == 0x3ff0000000000000L &&
              Double.doubleToRawLongBits(tiesEvenUp) == 0x3ff0000000000002L,
              "binary64 ties-to-even addition");


        int conversionInt = 16777217;
        float intToFloat = (float) conversionInt;
        double intToDouble = (double) conversionInt;
        long conversionLong = Long.MAX_VALUE;
        float longToFloat = (float) conversionLong;
        double longToDouble = (double) conversionLong;
        float conversionFloat = -3.75f;
        int floatToInt = (int) conversionFloat;
        long floatToLong = (long) conversionFloat;
        double floatToDouble = (double) conversionFloat;
        double conversionDouble = 3.75;
        int doubleToInt = (int) conversionDouble;
        long doubleToLong = (long) conversionDouble;
        long twoTo53 = 9007199254740992L;
        double roundedOddLong = (double) (twoTo53 + 1L);
        double roundedUpperLong = (double) (twoTo53 + 3L);
        double positiveLongLimit = 0x1.0p63;
        double belowNegativeLongLimit = -0x1.0000000000001p63;
        double doubleForFloatCast = 1.1;
        float doubleToFloat = (float) doubleForFloatCast;
        float hugeFloat = 1.0e30f;
        float negativeHugeFloat = -1.0e30f;
        double nanToConvert = nan;
        System.out.println(Float.floatToRawIntBits(intToFloat));
        System.out.println(intToDouble);
        System.out.println(Float.floatToRawIntBits(longToFloat));
        System.out.println(Double.doubleToRawLongBits(longToDouble));
        System.out.println(floatToInt);
        System.out.println(floatToLong);
        System.out.println(floatToDouble);
        System.out.println(doubleToInt);
        System.out.println(doubleToLong);
        System.out.println(Float.floatToRawIntBits(doubleToFloat));
        System.out.println((int) hugeFloat);
        System.out.println((long) hugeFloat);
        System.out.println((int) negativeHugeFloat);
        System.out.println((long) negativeHugeFloat);
        System.out.println((int) infinity);
        System.out.println((long) infinity);
        System.out.println((int) negativeInfinity);
        System.out.println((long) negativeInfinity);
        System.out.println((int) nanToConvert);
        System.out.println((long) nanToConvert);
        System.out.println(Double.doubleToRawLongBits(roundedOddLong));
        System.out.println(Double.doubleToRawLongBits(roundedUpperLong));
        System.out.println((long) positiveLongLimit);
        System.out.println((long) belowNegativeLongLimit);
        System.out.println((int) 2147483648.0);
        System.out.println((int) -2147483649.0);
        check(roundedOddLong == 9007199254740992.0 &&
              roundedUpperLong == 9007199254740996.0, "l2d ties near 2^53");
        check((long) positiveLongLimit == Long.MAX_VALUE &&
              (long) belowNegativeLongLimit == Long.MIN_VALUE, "d2l saturation limits");
        check((int) 2147483648.0 == Integer.MAX_VALUE &&
              (int) -2147483649.0 == Integer.MIN_VALUE, "d2i saturation limits");
        check(Float.floatToRawIntBits(intToFloat) == 0x4b800000, "i2f rounding");
        check(intToDouble == 16777217.0, "i2d");
        check(Float.floatToRawIntBits(longToFloat) == 0x5f000000, "l2f rounding");
        check(Double.doubleToRawLongBits(longToDouble) == 0x43e0000000000000L, "l2d rounding");
        check(floatToInt == -3 && floatToLong == -3L && floatToDouble == -3.75,
              "f2i/f2l/f2d truncation");
        check(doubleToInt == 3 && doubleToLong == 3L, "d2i/d2l truncation");
        check(Float.floatToRawIntBits(doubleToFloat) == 0x3f8ccccd, "d2f rounding");
        check((int) hugeFloat == Integer.MAX_VALUE && (long) hugeFloat == Long.MAX_VALUE,
              "f conversion positive saturation");
        check((int) negativeHugeFloat == Integer.MIN_VALUE &&
              (long) negativeHugeFloat == Long.MIN_VALUE, "f conversion negative saturation");
        check((int) infinity == Integer.MAX_VALUE && (long) infinity == Long.MAX_VALUE &&
              (int) negativeInfinity == Integer.MIN_VALUE &&
              (long) negativeInfinity == Long.MIN_VALUE, "d conversion saturation");
        check((int) nanToConvert == 0 && (long) nanToConvert == 0L, "NaN conversion");

        long wideResult = wideLocals();
        System.out.println(wideResult);
        check(wideResult == 0x123456788765442BL, "wide local load/store/iinc");

        try {
            WideHolder reflected = new WideHolder();
            java.lang.reflect.Field longValue = WideHolder.class.getDeclaredField("value");
            java.lang.reflect.Field doubleValue = WideHolder.class.getDeclaredField("decimal");
            longValue.setAccessible(true);
            doubleValue.setAccessible(true);
            longValue.setLong(reflected, 0x7123456789abcdefL);
            doubleValue.setDouble(reflected, -17.25d);
            check(longValue.getLong(reflected) == 0x7123456789abcdefL &&
                  doubleValue.getDouble(reflected) == -17.25d, "wide reflective field access");

            java.lang.reflect.Method method = WideSwitchFixture.class.getDeclaredMethod(
                "addWide", long.class, double.class);
            Object returned = method.invoke(null, new Object[] {
                Long.valueOf(0x1234567887654321L), Double.valueOf(3.75d)
            });
            check(((Long) returned).longValue() == 0x1234567887654324L,
                  "wide reflective invocation");

            java.lang.reflect.Constructor<?> constructor =
                WideHolder.class.getDeclaredConstructor(long.class);
            WideHolder constructed = (WideHolder) constructor.newInstance(
                new Object[] { Long.valueOf(0x2345678998765432L) });
            check(constructed.value == 0x2345678998765432L,
                  "wide reflective construction");
        } catch (Exception failure) {
            throw new AssertionError("wide reflection", failure);
        }

        java.lang.reflect.InvocationHandler wideHandler =
            new java.lang.reflect.InvocationHandler() {
                public Object invoke(Object proxy, java.lang.reflect.Method method,
                                     Object[] values) {
                    long base = ((Long) values[0]).longValue();
                    double adjustment = ((Double) values[1]).doubleValue();
                    return Long.valueOf(base + (long) adjustment);
                }
            };
        WideCallback callback = (WideCallback) java.lang.reflect.Proxy.newProxyInstance(
            WideSwitchFixture.class.getClassLoader(), new Class[] { WideCallback.class },
            wideHandler);
        check(callback.combine(0x3456789a98765432L, 5.75d) ==
              0x3456789a98765437L, "wide proxy callback");

        check(Long.parseLong("-9223372036854775808") == Long.MIN_VALUE &&
              Long.parseLong("9223372036854775807") == Long.MAX_VALUE,
              "Long.parseLong boundaries");
        expectLongParseFailure("9223372036854775808");
        expectLongParseFailure("-9223372036854775809");
        expectLongParseFailure("12x");
        expectLongParseFailure("");
        Long wideIdentity = Long.valueOf(0x1234567887654321L);
        check(Long.valueOf(127L) == Long.valueOf(127L),
              "Long.valueOf cache identity");

        check(wideIdentity.equals(Long.valueOf(0x1234567887654321L)) &&
              wideIdentity.hashCode() == (int) (0x1234567887654321L ^
                                                   (0x1234567887654321L >>> 32)),
              "Long equality and hashing");

        check(Double.isNaN(nan) && !Double.isInfinite(nan) &&
              Double.isInfinite(infinity) && !Double.isNaN(infinity),
              "Double classification");
        check(Double.valueOf(nan).equals(Double.valueOf(Double.NaN)) &&
              !Double.valueOf(-0.0d).equals(Double.valueOf(0.0d)) &&
              Double.valueOf(-0.0d).hashCode() != Double.valueOf(0.0d).hashCode(),
              "Double equality and hashing");
        check(Long.TYPE == long.class && Double.TYPE == double.class,
              "wide primitive mirrors");
        System.out.println(String.valueOf(WIDE_CONSTANT));
        System.out.println(new StringBuilder().append(DOUBLE_CONSTANT));

        WideMetadata metadata = WideAnnotated.class.getAnnotation(WideMetadata.class);
        check(metadata != null && metadata.value() == 0x1234567887654321L &&
              Double.doubleToRawLongBits(metadata.ratio()) == 0x8000000000000000L,
              "wide annotation defaults");
        System.out.println(dense(-2));
        System.out.println(dense(0));
        System.out.println(dense(2));
        System.out.println(dense(3));
        System.out.println(sparse(-1000));
        System.out.println(sparse(-7));
        System.out.println(sparse(42));
        System.out.println(sparse(99));
        check(dense(-2) == 20 && dense(0) == 0 && dense(2) == 22 && dense(3) == -99,
              "dense switch selection");
        check(sparse(-1000) == 1 && sparse(-7) == 2 && sparse(42) == 3 && sparse(99) == -1,
              "sparse switch selection");
        randomizedLongArithmetic();
        randomizedDoubleArithmetic();
    }
}
@java.lang.annotation.Retention(java.lang.annotation.RetentionPolicy.RUNTIME)
@interface WideMetadata {
    long value() default 0x1234567887654321L;
    double ratio() default -0.0d;
}

