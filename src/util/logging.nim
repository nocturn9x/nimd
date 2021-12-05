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
import posix
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
const logFile = "/var/log/nimd"
var logToFile: bool = false


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


proc logTraceStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgMagenta)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logDebugStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgCyan)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - DEBUG ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logInfoStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgGreen)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - INFO ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logWarningStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgYellow)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - WARNING ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logErrorStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgRed)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - ERROR ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logCriticalStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgRed)
    stderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - CRITICAL ({posix.getpid()})] {message}""")
    stderr.flushFile()
    setForegroundColor(fgDefault)


proc logFatalStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgBlack)
    setBackgroundColor(bgRed)
    stderr.write(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - FATAL ({posix.getpid()})]""")
    setForegroundColor(fgRed)
    setBackgroundColor(bgDefault)
    stderr.writeline(&" {message}")
    setForegroundColor(fgDefault)
    stderr.flushFile()


proc logTraceFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc logDebugFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc logInfoFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc logWarningFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")

proc logErrorFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc logCriticalFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc logFatalFile(self: LogHandler, logger: Logger, message: string) =
    StreamHandler(self).file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss")} - TRACE ({posix.getpid()})] {message}""")


proc switchToFile*(self: Logger) =
    ## Switches logging to file and
    ## changes the behavior of getDefaultLogger
    ## accordingly
    if logToFile:
        return
    logToFile = true
    self.handlers = @[]
    self.addHandler(createStreamHandler(logTraceFile, LogLevel.Trace, logFile))
    self.addHandler(createStreamHandler(logDebugFile, LogLevel.Debug, logFile))
    self.addHandler(createStreamHandler(logInfoFile, LogLevel.Info, logFile))
    self.addHandler(createStreamHandler(logWarningFile, LogLevel.Warning, logFile))
    self.addHandler(createStreamHandler(logErrorFile, LogLevel.Error, logFile))
    self.addHandler(createStreamHandler(logCriticalFile, LogLevel.Critical, logFile))
    self.addHandler(createStreamHandler(logFatalFile, LogLevel.Fatal, logFile))


proc getDefaultLogger*(): Logger =
    ## Gets a simple logger with level set
    ## to LogLevel.Info and one handler per
    ## level that writes the given message to the
    ## standard error with some basic info like the
    ## current date and time and the log level
    result = newLogger()
    if not logToFile:
        setStdIoUnbuffered()   # Colors don't work otherwise!
        result.addHandler(createHandler(logTraceStderr, LogLevel.Trace))
        result.addHandler(createHandler(logDebugStderr, LogLevel.Debug))
        result.addHandler(createHandler(logInfoStderr, LogLevel.Info))
        result.addHandler(createHandler(logWarningStderr, LogLevel.Warning))
        result.addHandler(createHandler(logErrorStderr, LogLevel.Error))
        result.addHandler(createHandler(logCriticalStderr, LogLevel.Critical))
        result.addHandler(createHandler(logFatalStderr, LogLevel.Fatal))
    else:
        result.addHandler(createStreamHandler(logTraceFile, LogLevel.Trace, logFile))
        result.addHandler(createStreamHandler(logDebugFile, LogLevel.Debug, logFile))
        result.addHandler(createStreamHandler(logInfoFile, LogLevel.Info, logFile))
        result.addHandler(createStreamHandler(logWarningFile, LogLevel.Warning, logFile))
        result.addHandler(createStreamHandler(logErrorFile, LogLevel.Error, logFile))
        result.addHandler(createStreamHandler(logCriticalFile, LogLevel.Critical, logFile))
        result.addHandler(createStreamHandler(logFatalFile, LogLevel.Fatal, logFile))
