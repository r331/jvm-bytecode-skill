#!/bin/sh
# Fake agent for the self-test: writes Java source and a hand-made .class
# without any .hex.
cd "${WORKDIR:?}"
printf 'public class Foo { public static void main(String[] a) {} }\n' > Foo.java
printf '\312\376\272\276\000\000\000\101' > Foo.class
exit 0
