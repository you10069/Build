#!/bin/bash

flags=$(grep -m1 flags /proc/cpuinfo)

supports() { echo "$flags" | grep -qw "$1"; }

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
reset="\033[0m"

print_flag() {
    if supports "$1"; then
        echo -e "  ${green}$1 ✔${reset}"
    else
        echo -e "  ${red}$1 ✘${reset}"
    fi
}

echo -e "${yellow}v2:${reset}"
for f in aes ssse3 sse4_1 sse4_2 popcnt cx16 lahf_lm; do
    print_flag "$f"
done

echo -e "${yellow}v3:${reset}"
for f in avx avx2 bmi1 bmi2 fma movbe xsave lzcnt osxsave; do
    print_flag "$f"
done

echo -e "${yellow}v4:${reset}"
for f in avx512f avx512bw avx512cd avx512dq avx512vl; do
    print_flag "$f"
done

# 自动判断 GOAMD64 级别
level=1
supports sse4_2 && level=2
supports avx2 && level=3
supports avx512f && level=4

echo ""
echo -e "${yellow}Your CPU supports: GOAMD64=v${level}${reset}"
