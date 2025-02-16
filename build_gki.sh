#!/bin/bash
#
# init


WORK_DIR=$(pwd)
KERNEL_DIR="common"
LOG_FILE="log.txt"

# setup color
red='\033[0;31m'
green='\e[0;32m'
white='\033[0m'
yellow='\033[0;33m'

function clean() {
    echo -e "\n"
    echo -e "$red << cleaning up >> \n$white" | tee -a $LOG_FILE
    echo -e "\n" | tee -a $LOG_FILE
    rm -rf ${ANYKERNEL}
    rm -rf out
}

function build_kernel() {
    echo -e "\n"
    echo -e "$yellow << building kernel >> \n$white" | tee -a $LOG_FILE
    echo -e "\n" | tee -a $LOG_FILE
    
    cd $WORK_DIR

    # Record start time
    start_time=$(date +%s)

    LTO=thin BUILD_CONFIG=$KERNEL_DIR/build.config.gki.aarch64 build/build.sh | tee -a $LOG_FILE

    # Record end time
    end_time=$(date +%s)
    compile_time=$((end_time - start_time))

    if [ -e "$KERN_IMG" ]; then
        echo -e "\n"
        echo -e "$green << compile kernel success! >> \n$white" | tee -a $LOG_FILE
        echo -e "Compile time: $compile_time seconds" | tee -a $LOG_FILE
        echo -e "\n" | tee -a $LOG_FILE
        pack_kernel
    else
        echo -e "\n"
        echo -e "$red << compile kernel failed! >> \n$white" | tee -a $LOG_FILE
        echo -e "\n" | tee -a $LOG_FILE
    fi
}

# exe
clean
build_kernel