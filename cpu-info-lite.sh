for f in aes ssse3 sse4_1 sse4_2 popcnt cx16 lahf_lm avx avx2 bmi1 bmi2 fma movbe xsave lzcnt osxsave; do grep -qw "$f" /proc/cpuinfo && printf "%s\n" "$f"; done
