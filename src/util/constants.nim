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
import strformat


const NimDVersion*: tuple[major, minor, patch: int] = (major: 0, minor: 0, patch: 1)
const NimDVersionString* = &"NimD version {NimDVersion.major}.{NimDVersion.minor}.{NimDVersion.patch} ({CompileDate}, {CompileTime}, {hostOS}, {hostCPU}) compiled with Nim {NimVersion}"
const helpMessage* = """The NimD init system, Copyright (C) 2021 Mattia Giambirtone & All contributors

This program is free software, see the license distributed with this program or check
http://www.apache.org/licenses/LICENSE-2.0 for more info.


Command-line options
--------------------
-h, --help     -> Shows this help text and exit
-v, --version  -> Prints the NimD version number and exits
-V, --verbose  -> Enables debug output
-X, --extra    -> Enables extra verbose output (hint: you probably don't need it)"""