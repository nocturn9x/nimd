# Copyright 2021 Mattia Giambirtone & All Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import tables
import parsecfg
import strutils
import strformat


import ../util/logging
import services
import fs


type
    NimDConfig* = ref object
        ## Configuration object
        logLevel*: LogLevel
        logDir*: Directory
        services*: tuple[runlevel: RunLevel, services: seq[Service]]
        directories*: seq[Directory]
        symlinks*: seq[Symlink]
        filesystems*: seq[Filesystem]
        restartDelay*: int
        autoMount*: bool
        autoUnmount*: bool
        fstab*: string
        sock*: string


const defaultSections = ["Misc", "Logging", "Filesystem"]
const defaultConfig = {
                  "Logging": {
                        "stderr": "/var/log/nimd",
                        "stdout": "/var/log/nimd",
                        "level": "info"
                        }.toTable(),
                  "Misc": {
                        "controlSocket": "/var/run/nimd.sock",
                        "onDependencyConflict": "skip"
                        }.toTable(),
                  "Filesystem": {
                        "autoMount": "true",
                        "autoUnmount": "true",
                        "fstabPath": "/etc/fstab",
                        "createDirs": "",
                        "createSymlinks": "",
                        "virtualDisks": ""
                  }.toTable()
                }.toTable()
const levels = {"trace": Trace, "debug": Debug, "info": Info,
                "warning": Warning, "error": Error, "critical": Critical, 
                "fatal": Fatal}.toTable()


proc parseConfig*(logger: Logger, file: string = "/etc/nimd/nimd.conf"): NimDConfig =
    ## Parses NimD's configuration file
    ## and returns a configuration object
    
    # Yes this code is far from perfect, but I hate paesing
    # config files :(
    logger.debug(&"Reading config file at {file}")
    let cfgObject = loadConfig(file)
    var data = newTable[string, TableRef[string, string]]()
    var existingSections: seq[string] = @[]
    var directories: seq[Directory] = @[]
    var filesystems: seq[Filesystem] = @[]
    var symlinks: seq[Symlink] = @[]
    var temp: seq[string] = @[]
    for section in cfgObject.sections():
        existingSections.add(section)
    for section in defaultSections:
        logger.debug(&"Parsing section '{section}'")
        if section notin existingSections:
            logger.warning(&"Missing section '{section}' from config file, falling back to defaults")
            for (value, key) in defaultConfig[section].pairs():
                data[section][value] = key
        elif section notin defaultSections:
            logger.warning(&"Unknown section '{section}' found in config file, skipping it")
        else:
            for key in defaultConfig[section].keys():
                data[section][key] = cfgObject.getSectionValue(section, key, defaultConfig[section][key])
    for dirInfo in data["Filesystem"]["createDirs"].split(","):
        temp = dirInfo.split(":")
        directories.add(newDirectory(temp[0], uint64(parseInt(temp[1]))))
    for symInfo in data["Filesystem"]["createSymlinks"].split(","):
        temp = symInfo.split(":")
        symlinks.add(newSymlink(temp[0], temp[1]))
    if data["Logging"]["level"] notin levels:
        logger.warning(&"""Unknown logging level '{data["Logging"]["level"]}', defaulting to {defaultConfig["Logging"]["level"]}""")
        data["Logging"]["level"] = defaultConfig["Logging"]["level"]
    result = NimDConfig(logLevel: levels[data["Logging"]["level"]],
                        filesystems: filesystems)