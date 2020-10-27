#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

script_directory="$(cd "$(dirname "$0")" && pwd)"

add_option(){
  eval "$1=$2"
  OPTIONS+=("$1")
  CMAKE_OPTIONS_ENABLED+=("$1:$3")
  CMAKE_OPTIONS_DISABLED+=("$1:$4")
}

add_enabled_option(){
  eval "$1=$2"
  OPTIONS+=("$1")
  CMAKE_OPTIONS_ENABLED+=("$1:$3")
}
add_cmake_option(){
  eval "$1=$2"
}

add_disabled_option(){
  eval "$1=$2"
  OPTIONS+=("$1")
  CMAKE_OPTIONS_ENABLED+=("$1:$3")
  if [ ! -z "$4" ]; then
    CMAKE_MIN_VERSION+=("$1:$4")
  fi

  if [ ! -z "$5" ]; then
    if [ "$5" = "true" ]; then
      DEPLOY_LIMITS+=("$1")
    fi
  fi
}

add_dependency(){
  DEPENDENCIES+=("$1:$2")
}

### parse the command line arguments


EnableAllFeatures(){
  for option in "${OPTIONS[@]}" ; do
    feature_status=${!option}
    if [ "$feature_status" = "${FALSE}" ]; then
      ToggleFeature $option
    fi
    #	eval "$option=${TRUE}"
  done
}

pause(){
  read -p "Press [Enter] key to continue..." fackEnterKey
}

load_options() {
  input="${script_directory}/features.list"
  LINEMAP=()
  while IFS= read -r line
  do
    if ! [[ "$line" =~ ^#.* ]]; then
      ## option.name will be the 
      if [[ "$line" =~ ^option.name=.* ]]; then
        VARIABLE=`echo $line | cut -d '=' -f 2`
        OPTION_DESCRIPTIONS+=("${VARIABLE}")
      else
        VAR=`echo $line | cut -d '=' -f 1`
        VAL=`echo $line | cut -d '=' -f 2`
        eval "${VAR}=\"${VAL}\""
      fi
    fi
  done < "$input"
  for option in "${OPTION_DESCRIPTIONS[@]}" ; do
    OPT=${option%%:*}
    DEFAULT_NAME="${OPT}_default"
    DEP_NAME="${OPT}_dependencies"
    DEF_V=${!DEFAULT_NAME}
    DEP_V=${!DEP_NAME}
    if [ "$DEF_V" == "${TRUE}" ] || [ "$DEF_V" == "TRUE"  ]; then
      add_enabled_option $OPT ${TRUE} "$OPT"
    else
      add_disabled_option $OPT ${FALSE} "$OPT"
    fi  
    echo $DEP_V | sed -n 1'p' | tr ',' '\n' | while read dependency; do
      add_dependency $OPT "$dependency"
    done
  done
}



load_state(){
  if [ -f ${script_directory}/bt_state ]; then
    . ${script_directory}/bt_state
    for option in "${OPTIONS[@]}" ; do
      option_value="${!option}"
      if [ "${option_value}" = "${FALSE}" ]; then
        ALL_FEATURES_ENABLED=${FALSE}
      fi
    done
  fi
}

echo_state_variable(){
  VARIABLE_VALUE=${!1}
  echo "$1=\"${VARIABLE_VALUE}\"" >> ${script_directory}/bt_state
}

save_state(){
  echo "VERSION=1" > ${script_directory}/bt_state
  echo_state_variable BUILD_IDENTIFIER
  echo_state_variable BUILD_DIR
  for option in "${OPTIONS[@]}" ; do
    echo_state_variable $option
  done
}

can_deploy(){
  for option in "${DEPLOY_LIMITS[@]}" ; do
    OPT=${option%%:*}
    if [ "${OPT}" = "$1" ]; then
      echo "false"
    fi
  done
  echo "true"
}

ToggleFeature(){
  VARIABLE_VALUE=${!1}
  ALL_FEATURES_ENABLED="Disabled"
  if [ $VARIABLE_VALUE = "Enabled" ]; then
    eval "$1=${FALSE}"
  else
    for option in "${CMAKE_MIN_VERSION[@]}" ; do
      OPT=${option%%:*}
      if [ "$OPT" = "$1" ]; then
        NEEDED_VER=${option#*:}
        NEEDED_MAJOR=`echo $NEEDED_VER | cut -d. -f1`
        NEEDED_MINOR=`echo $NEEDED_VER | cut -d. -f2`
        NEEDED_REVISION=`echo $NEEDED_VERSION | cut -d. -f3`
        if (( NEEDED_MAJOR > CMAKE_MAJOR )); then
          return 1
        fi

        if (( NEEDED_MINOR > CMAKE_MINOR )); then
          return 1
        fi

        if (( NEEDED_REVISION > CMAKE_REVISION )); then
          return 1
        fi
      fi
    done
    CAN_ENABLE=$(verify_enable $1)
    CAN_DEPLOY=$(can_deploy $1)
    if [ "$CAN_ENABLE" = "true" ]; then
      if [[ "$DEPLOY" = "true" &&  "$CAN_DEPLOY" = "true" ]] || [[ "$DEPLOY" = "false" ]]; then
        eval "$1=${TRUE}"
      fi
    fi
  fi
}


print_feature_status(){
  feature="$1"
  feature_status=${!1}
  if [ "$feature_status" = "Enabled" ]; then
    echo "Enabled"
  else
    for option in "${CMAKE_MIN_VERSION[@]}" ; do
      OPT=${option%%:*}
      if [ "${OPT}" = "$1" ]; then
        NEEDED_VER=${option#*:}
        NEEDED_MAJOR=`echo $NEEDED_VER | cut -d. -f1`
        NEEDED_MINOR=`echo $NEEDED_VER | cut -d. -f2`
        NEEDED_REVISION=`echo $NEEDED_VERSION | cut -d. -f3`
        if (( NEEDED_MAJOR > CMAKE_MAJOR )); then
          echo -e "${RED}Disabled*${NO_COLOR}"
          return 1
        fi

        if (( NEEDED_MINOR > CMAKE_MINOR )); then
          echo -e "${RED}Disabled*${NO_COLOR}"
          return 1
        fi

        if (( NEEDED_REVISION > CMAKE_REVISION )); then
          echo -e "${RED}Disabled*${NO_COLOR}"
          return 1
        fi
      fi
    done
    CAN_ENABLE=$(verify_enable $1)
    if [ "$CAN_ENABLE" = "true" ]; then
      echo -e "${RED}Disabled${NO_COLOR}"
    else
      echo -e "${RED}Disabled*${NO_COLOR}"
    fi

  fi
}

show_supported_features() {
  clear
  max_len=0
  MY_OPTS=({0..9} {A..Z} _)
  LOC=0
  for option in "${OPTION_DESCRIPTIONS[@]}" ; do
    OPT=${option%%:*}
    DESCRIPTION_NAME="${OPT}_description"
    
    DESC_V=${!DESCRIPTION_NAME}
    DESC_LEN=${#DESC_V}
    if [ "$DESC_LEN" -gt "$max_len" ]; then
      max_len=$((DESC_LEN+5))
    fi
  done

  echo "****************************************"
  echo " Configure your build."
  echo "****************************************"
  for option in "${OPTION_DESCRIPTIONS[@]}" ; do
  OPT=${option%%:*}
  DESCRIPTION_NAME="${OPT}_description"
  
  DESC_V=${!DESCRIPTION_NAME}
  DESC_LEN=${#DESC_V}
  STARS_LEN=$((max_len-DESC_LEN))
  STARS=`printf %${STARS_LEN}s |tr " " "*"`

  echo "${MY_OPTS[LOC]}. ${DESC_V} ${STARS} $(print_feature_status $OPT)"  
  ((++LOC))
  done

  echo "P. Continue with these options"
  if [ "$GUIDED_INSTALL" = "${TRUE}" ]; then
    echo "R. Return to Main Menu"
  fi
  echo "Q. Quit"
  echo "* Extension cannot be installed due to"
  echo -e "  version of cmake or other software\r\n"
}

read_feature_options(){
  local choice
  read -p "Enter choice " choice
  choice=$(echo ${choice} | tr '[:upper:]' '[:lower:]')
  
  MY_OPTS=({0..9} {A..Z} _)
  LOC=0
  for option in "${OPTION_DESCRIPTIONS[@]}" ; do
    OPT=${option%%:*}
    if [ "$choice" ==  "${MY_OPTS[LOC]}" ]; then
      ToggleFeature $OPT
      return
    fi
    ((++LOC))
  done
  
  if [ "$choice" ==  "p" ]; then
    FEATURES_SELECTED="true" 
  elif [ "$choice" ==  "q" ]; then
    exit 0
  else
    echo -e "${RED}Please enter an option A-T or 1-4...${NO_COLOR}" && sleep 2
  fi
}

