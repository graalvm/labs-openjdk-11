/*
 * Copyright (c) 2019, 2019, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/**
 * @test
 * @bug 8233090
 * @summary Check if disabling eager initialization works
 *   Test a stack trace of initialized lambda and see that
 *   it does not contain the LambdaMetaFactory
 * @compile LambdaInitializationTest.java
 * @run main LambdaInitializationTest
 * @run main/othervm -Djdk.internal.lambda.disableEagerInitialization=TRUE LambdaInitializationTest
 */

import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Set;

public class LambdaInitializationTest {

    interface H {
        public static Exception trace = new Exception();

        void m();

        /** Initializes H together with a lambda. */
        default double lambda() {
            return 1.1056E-52;
        }
    }

    private static void assertTrue(boolean b, String msg) {
        if(!b)
            throw new AssertionError(msg);
    }

    private void test1() {
        H la = () -> { };
        la.m();
        boolean containsLMF = false;
        boolean initialized = false;
        for (StackTraceElement element : H.trace.getStackTrace()) {
            containsLMF = containsLMF || element.getClassName().contains("LambdaMetafactory");
            initialized = true;
        }

        assertTrue(initialized, "Has a stack");
        assertTrue(containsLMF ^ "TRUE".equals(System.getProperty("jdk.internal.lambda.disableEagerInitialization")),
            "Either has LambdaMetaFactory in the stack or the eager initialization is disabled");
    }

    public static void main(String[] args) {
        LambdaInitializationTest test = new LambdaInitializationTest();
        test.test1();
    }
}
