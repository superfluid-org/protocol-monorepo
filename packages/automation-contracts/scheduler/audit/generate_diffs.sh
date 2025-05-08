#!/bin/bash

git diff -U9999 --no-index --minimal --ignore-cr-at-eol --ignore-space-at-eol ./../contracts/interface/IVestingScheduler.sol ./../contracts/interface/IVestingSchedulerV2.sol > diff_IVestingScheduler_vs_IVestingSchedulerV2.txt
git diff -U9999 --no-index --minimal --ignore-cr-at-eol --ignore-space-at-eol ./../contracts/VestingScheduler.sol ./../contracts/VestingSchedulerV2.sol > diff_VestingScheduler_vs_VestingSchedulerV2.txt