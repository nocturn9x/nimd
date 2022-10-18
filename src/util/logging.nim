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


import cffi

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


var defaultLevel = LogLevel.Info
var logFile = "/var/log/nimd"
var logToFileOnly: bool = false


proc setLogFile*(file: string) =
    # Sets the log file
    logFile = file


## This mess is needed to make sure stderr writes are mostly atomic. Sort of.
## No error handling yet. Deal with it
var customStderrFd = dup(stderr.getFileHandle())
discard dup3(stderr.getFileHandle(), customStderrFd, O_APPEND)
var customStderr: File
discard open(customStderr, customStderrFd, fmAppend)


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
proc setLogFile*(filename: string) = logFile = filename
proc getLogFile*: string = logFile
proc setDefaultLevel*(level: LogLevel) = defaultLevel = level
proc getDefaultLevel*: LogLevel = defaultLevel
proc createHandler*(procedure: proc (self: LogHandler, logger: Logger, message: string), level: LogLevel): LogHandler = LogHandler(code: procedure, level: level)
proc createStreamHandler*(procedure: proc (self: LogHandler, logger: Logger, message: string), level: LogLevel, filename: string): StreamHandler = StreamHandler(code: procedure, level: level, filename: filename, file: open(filename, fmAppend))
proc addHandler*(self: Logger, handler: LogHandler) = self.handlers.add(handler)
proc removeHandler*(self: Logger, handler: LogHandler) = self.handlers.delete(self.handlers.find(handler))


proc log(self: Logger, level: LogLevel = defaultLevel, message: string) =
    ## Generic utility for logging on any level
    for handler in self.handlers:
        if handler.level == level and self.level <= level:
            handler.code(handler, self, message)


# Note: Log messages have been *carefully* hand tuned to be perfectly aligned both in the console and in log files.
# Do NOT touch the alignment offsets or your console output and logs will look like trash



proc logTraceStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgMagenta)
    customStderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} TRACE {"-":>3} ({posix.getpid():03})] {message}""")
    setForegroundColor(fgDefault)


proc logDebugStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgCyan)
    customStderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} DEBUG {"-":>3} ({posix.getpid():03})] {message}""")
    setForegroundColor(fgDefault)


proc logInfoStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgGreen)
    customStderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} INFO {"-":>4} ({posix.getpid():03})] {message}""")
    setForegroundColor(fgDefault)


proc logWarningStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgYellow)
    customStderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} WARNING {"-":>1} ({posix.getpid():03})] {message}""")
    setForegroundColor(fgDefault)


proc logErrorStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgRed)
    customStderr.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} ERROR {"-":>3} ({posix.getpid():03})] {message}""")
    setForegroundColor(fgDefault)
    

proc logCriticalStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgYellow)
    setBackgroundColor(bgRed)
    customStderr.write(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<4} {"-":>1} CRITICAL {"-":>2} ({posix.getpid():03})]""")
    setBackgroundColor(bgDefault)
    customStderr.writeLine(&""" {message}""")
    setForegroundColor(fgDefault)
    

proc logFatalStderr(self: LogHandler, logger: Logger, message: string) =
    setForegroundColor(fgBlack)
    setBackgroundColor(bgRed)
    customStderr.write(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<5} {"-":>1} {"":>1} FATAL {"-":>3} ({posix.getpid():03})]""")
    setForegroundColor(fgRed)
    setBackgroundColor(bgDefault)
    customStderr.writeline(&""" {message}""")
    setForegroundColor(fgDefault)
    

proc logTraceFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} TRACE {"-":>3} ({posix.getpid():03})] {message}""")
    

proc logDebugFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} DEBUG {"-":>3} ({posix.getpid():03})] {message}""")
    

proc logInfoFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} INFO {"-":>4} ({posix.getpid():03})] {message}""")
    

proc logWarningFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} WARNING {"-":>1} ({posix.getpid():03})] {message}""")


proc logErrorFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<10} {"-":>1} {"":>1} ERROR {"-":>3} ({posix.getpid():03})] {message}""")
    


proc logCriticalFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<4} {"-":>1} CRITICAL {"-":>2} ({posix.getpid():03})] {message}""")
    

proc logFatalFile(self: LogHandler, logger: Logger, message: string) =
    var self = StreamHandler(self)
    self.file.writeLine(&"""[{fromUnix(getTime().toUnixFloat().int).format("d/M/yyyy HH:mm:ss"):<5} {"-":>1} {"":>1} FATAL {"-":>3} ({posix.getpid():03})] {message}""")
    


proc switchToFile*(self: Logger) =
    ## Switches logging to file and
    ## changes the behavior of getDefaultLogger
    ## accordingly
    if logToFileOnly:
        return
    self.handlers = @[]   # Don't you love it when you can just let the GC manage memory for you?
    self.addHandler(createStreamHandler(logTraceFile, LogLevel.Trace, logFile))
    self.addHandler(createStreamHandler(logDebugFile, LogLevel.Debug, logFile))
    self.addHandler(createStreamHandler(logInfoFile, LogLevel.Info, logFile))
    self.addHandler(createStreamHandler(logWarningFile, LogLevel.Warning, logFile))
    self.addHandler(createStreamHandler(logErrorFile, LogLevel.Error, logFile))
    self.addHandler(createStreamHandler(logCriticalFile, LogLevel.Critical, logFile))
    self.addHandler(createStreamHandler(logFatalFile, LogLevel.Fatal, logFile))


proc switchToConsole*(self: Logger) =
    ## Switches logging to the console and
    ## changes the behavior of getDefaultLogger
    ## accordingly
    if not logToFileOnly:
        return
    self.handlers = @[]
    self.addHandler(createHandler(logTraceStderr, LogLevel.Trace))
    self.addHandler(createHandler(logDebugStderr, LogLevel.Debug))
    self.addHandler(createHandler(logInfoStderr, LogLevel.Info))
    self.addHandler(createHandler(logWarningStderr, LogLevel.Warning))
    self.addHandler(createHandler(logErrorStderr, LogLevel.Error))
    self.addHandler(createHandler(logCriticalStderr, LogLevel.Critical))
    self.addHandler(createHandler(logFatalStderr, LogLevel.Fatal))


proc getDefaultLogger*: Logger =
    ## Gets a simple logger with level set
    ## to LogLevel.Info and one handler per
    ## level that writes the given message to the
    ## standard error with some basic info like the
    ## current date and time and the log level
    result = newLogger()
    if not logToFileOnly:
        result.addHandler(createHandler(logTraceStderr, LogLevel.Trace))
        result.addHandler(createHandler(logDebugStderr, LogLevel.Debug))
        result.addHandler(createHandler(logInfoStderr, LogLevel.Info))
        result.addHandler(createHandler(logWarningStderr, LogLevel.Warning))
        result.addHandler(createHandler(logErrorStderr, LogLevel.Error))
        result.addHandler(createHandler(logCriticalStderr, LogLevel.Critical))
        result.addHandler(createHandler(logFatalStderr, LogLevel.Fatal))
    result.addHandler(createStreamHandler(logTraceFile, LogLevel.Trace, logFile))
    result.addHandler(createStreamHandler(logDebugFile, LogLevel.Debug, logFile))
    result.addHandler(createStreamHandler(logInfoFile, LogLevel.Info, logFile))
    result.addHandler(createStreamHandler(logWarningFile, LogLevel.Warning, logFile))
    result.addHandler(createStreamHandler(logErrorFile, LogLevel.Error, logFile))
    result.addHandler(createStreamHandler(logCriticalFile, LogLevel.Critical, logFile))
    result.addHandler(createStreamHandler(logFatalFile, LogLevel.Fatal, logFile))
