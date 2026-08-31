#!/bin/bash

# 1. 记录 Sioyek 传进来的参数
echo "===== $(date) =====" >> /tmp/sioyek_shell_debug.log
echo "Sioyek 传入了参数: [$1]" >> /tmp/sioyek_shell_debug.log

# 2. 调用你的 Python 脚本，并把所有输出（包括报错）写入日志
/home/moqsien/.vmr/versions/miniconda_versions/miniconda/bin/python "/home/moqsien/.config/sioyek/kindle_dict.py" "$1" >> /tmp/sioyek_shell_debug.log 2>&1

# 3. 记录执行结果
echo "Python 执行完毕，退出码: $?" >> /tmp/sioyek_shell_debug.log

