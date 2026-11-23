#!/bin/bash

FILELIST=""
TOP_MODULE=""
GUI_MODE=0
UVM_MODE=0
C_FILE=""
# [미래 확장용] TESTNAME="" 

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -f) FILELIST="$2"; shift ;;
        -top) TOP_MODULE="$2"; shift ;;
        -gui) GUI_MODE=1 ;;
        -uvm) UVM_MODE=1 ;;
        -c) C_FILE="$2"; shift ;;
        # [미래 확장용] -test) TESTNAME="$2"; shift ;;
        *) echo "알 수 없는 옵션: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$FILELIST" ] || [ -z "$TOP_MODULE" ]; then
    echo "사용법: ./Scripts/sim.sh -f <filelist.f> -top <top_module_name> [-gui] [-uvm] [-c <dpi_c_file>]"
    # [미래 확장용] echo "사용법: ./Scripts/sim.sh -f <filelist.f> -top <top_module_name> [-gui] [-uvm] [-c <dpi_c_file>] [-test <test_name>]"
    exit 1
fi

echo "=================================================="
echo "🚀 시뮬레이션 시작: $TOP_MODULE"
echo "=================================================="

mkdir -p Vivado/$TOP_MODULE
mkdir -p Vivado/__Synthesis
cd Vivado/$TOP_MODULE

echo "[1/3] xvlog 컴파일 중..."
if [ "$UVM_MODE" -eq 1 ]; then
    cmd.exe /c xvlog.bat -sv -L uvm -f ../../$FILELIST
else
    cmd.exe /c xvlog.bat -sv -f ../../$FILELIST
fi
if [ $? -ne 0 ]; then echo "❌ xvlog 에러!"; cd ../..; exit 1; fi

if [ -n "$C_FILE" ]; then
    echo "[DPI-C] xsc 컴파일 중..."
    cmd.exe /c xsc.bat ../../$C_FILE
    if [ $? -ne 0 ]; then echo "❌ xsc 에러!"; cd ../..; exit 1; fi
fi

echo "[2/3] xelab Elaboration 중..."
# 타임스케일 에러 방지 및 멀티코어(-mt max) 적용 완료
SV_LIB_ARG=""
if [ -n "$C_FILE" ]; then
    SV_LIB_ARG="-sv_lib dpi"
fi

if [ "$UVM_MODE" -eq 1 ]; then
    cmd.exe /c xelab.bat -debug typical -timescale 1ns/1ps -mt auto -L uvm $SV_LIB_ARG -top $TOP_MODULE -snapshot ${TOP_MODULE}_snap
else
    cmd.exe /c xelab.bat -debug typical -timescale 1ns/1ps -mt auto $SV_LIB_ARG -top $TOP_MODULE -snapshot ${TOP_MODULE}_snap
fi
if [ $? -ne 0 ]; then echo "❌ xelab 에러!"; cd ../..; exit 1; fi

echo "[3/3] xsim 시뮬레이션 실행 중..."

# [미래 확장용] UVM_ARG=""
# [미래 확장용] if [ -n "$TESTNAME" ]; then
# [미래 확장용]     UVM_ARG="-testplusarg UVM_TESTNAME=$TESTNAME"
# [미래 확장용] fi

if [ "$GUI_MODE" -eq 1 ]; then
    # [미래 확장용] cmd.exe /c xsim.bat ${TOP_MODULE}_snap $UVM_ARG -gui
    cmd.exe /c xsim.bat ${TOP_MODULE}_snap -gui
else
    # [미래 확장용] cmd.exe /c xsim.bat ${TOP_MODULE}_snap $UVM_ARG -R
    cmd.exe /c xsim.bat ${TOP_MODULE}_snap -R
fi

cd ../..
echo "✅ 시뮬레이션 완료!"
