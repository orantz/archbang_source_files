#!/bin/bash
exe=$(dmenu_run -fn 'Sans-9:normal' -nb '#000000' -nf '#FFFFFF' -sb '#518F2B' -sf '#000000') && eval "exec $exe"
