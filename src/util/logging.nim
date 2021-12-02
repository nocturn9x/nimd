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

# A simple logging module inspired by python's own logging facility
import terminal
import strformat
import times


type
    LogLevel* = enum
        Trace = 0,
        Debug = 10,
        Info = 20,
        Warning = 30,
        Error  = 40,
        Critical = 50,
        Fatal = 60
    LogHandler* = ref object of RootObj
        code: proc (self: LogHandler, logger: Logger, message: string)
        level: LogLevel
    StreamHandler* = ref object of LogHandler
        filename*: string
        file*: File
    Logger* = ref object
        level*: LogLevel
        handlers*: seq[LogHandler]

const defaultLevel = LogLevel.Info

proc log(self: Logger, level: LogLevel = defaultLevel, message: string)  # Forward declaration

# Simple one-line procedures

proc trace*(self: Logger, message: string) = self.log(LogLevel.Trace, message)
proc debug*(self: Logger, message: string) = self.log(LogLevel.Debug, message)
proc info*(self: Logger, message: string) = self.log(LogLevel.Info, message)
proc warning*(self: Logger, message: string) = self.log(LogLevel.Warning, message)
proc error*(self: Logger, message: string) = self.log(LogLevel.Error, message)
proc critical*(self: Logger, message: string) = self.log(LogLevel.Critical, message)
proc fatal*(self: Logger, message: string) = self.log(LogLevel.Fatal, message)

proc newLogger*(level: LogLevel = defaultLevel, handlers: seq[LogHandler] = @[]): Logger = Logger(level: level, handlers: handlers)
proc setLevel*(self: Logger, level: LogLevel) = self.level = level
proc getLevel*(self: Logger): LogLevel = self.level
proc createHandler*(procedure: proc (self: LogHandler, logger: Logger, message: string), level: LogLevel): LogHandler = LogHandler(code: procedure, level: level)
proc createStreamHandler*(procedure: proc (self: LogHandler, logger: Logger, message: string), level: LogLevel, filename: string): StreamHandler = StreamHandler(code: procedure, level: level, filename: filename, file: open(filename, fmWrite))
proc addHandler*(self: Logger, handler: LogHandler) = self.handlers.add(handler)
proc removeHandler*(self: Logger, handler: LogHandler) = self.handlers.delete(self.handlers.find(handler))


proc log(self: Logger, level: LogLevel = defaultLevel, message: string) =
    ## Generic utility for logging on any level
    for handler in self.handlers:
        if handler.level == level and self.level <= level:
            handler.code(handler, self, message)


proc getDefaultLogger*(): Logger =
    ## Gets a simple logger with level set
    ## to LogLevel.Info and one handler per
    ## level that writes the given message to the
    ## standard error with some basic info like the
    ## current date and time and the log level
    
    setStdIoUnbuffered()   # Just in case

    proc logTrace(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgMagenta)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE] {message}""")
        setForegroundColor(fgDefault)
    
    proc logDebug(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgCyan)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - DEBUG] {message}""")
        setForegroundColor(fgDefault)

    proc logInfo(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgGreen)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - INFO] {message}""")
        setForegroundColor(fgDefault)

    proc logWarning(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgYellow)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - WARNING] {message}""")
        setForegroundColor(fgDefault)

    proc logError(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgRed)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - ERROR] {message}""")
        setForegroundColor(fgDefault)

    proc logCritical(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgRed)
        stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - CRITICAL] {message}""")
        setForegroundColor(fgDefault)

    proc logFatal(self: LogHandler, logger: Logger, message: string) =
        setForegroundColor(fgBlack)
        setBackgroundColor(bgRed)
        stderr.write(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - FATAL]""")
        setForegroundColor(fgRed)
        setBackgroundColor(bgDefault)
        stderr.writeline(&" {message}")
        setForegroundColor(fgDefault)

    result = newLogger()
    result.addHandler(createHandler(logTrace, LogLevel.Trace))
    result.addHandler(createHandler(logDebug, LogLevel.Debug))
    result.addHandler(createHandler(logInfo, LogLevel.Info))
    result.addHandler(createHandler(logWarning, LogLevel.Warning))
    result.addHandler(createHandler(logError, LogLevel.Error))
    result.addHandler(createHandler(logCritical, LogLevel.Critical))
    result.addHandler(createHandler(logFatal, LogLevel.Fatal))
