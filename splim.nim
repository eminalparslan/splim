import os, parseopt, strformat
import std/[strutils, re, streams, rdstdin]

type
  Track = object
    name: string
    ss: string
    to: string

proc parseTimestamps(timestamps: string): seq[Track] =
  let strm = newFileStream(timestamps)
  defer: strm.close()
  var tracks: seq[Track] = @[]

  let regex = re"((?:\d:)?(?:\d\d:)*\d\d)"

  var line1, line2: string
  var match: array[1, string]
  while strm.readLine(line1) and strm.peekLine(line2):
    var track: Track
    if line1.contains(regex, match):
      track.ss = match[0]
    if line2.contains(regex, match):
      track.to = match[0]
    track.name = line1
                  .replace(regex, "")
                  .replace("\"", "'") # prevent names escaping strings
                  .replace("/", "")   # prevent names interpreted as paths
                  .replace("()", "")  # if timestamp parenthasized
                  .strip()
                  .strip(leading=true, trailing=true, chars={'-'})
                  .strip()
    tracks.add(track)

  if line1.contains(regex, match):
    tracks.add(Track(
      name: line1.replace(regex, "").strip(),
      ss: match[0],
      to: ""
    ))
  return tracks

proc splim(input: string, output: string, tracks: seq[Track]) =
  if not dirExists(output):
    createDir(output)
  var commands: seq[string] = @[]
  for i, track in tracks:
    var command: string
    if i == len(tracks)-1:
      command = &"ffmpeg -ss {track.ss} -i \"{input}\" -c copy \"{output}/{track.name}.mp3\""
    else:
      command = &"ffmpeg -ss {track.ss} -to {track.to} -i \"{input}\" -c copy \"{output}/{track.name}.mp3\""
    echo command
    commands.add(command)
  while true:
    let input = readLineFromStdin("Does this seem ok? (Y/n) ")
    case input
    of "", "y", "Y": break
    of "n", "N":
      let tmpPath = &"{getTempDir()}/splim.tmp"
      let tmpFile = open(tmpPath, fmReadWrite)
      defer: tmpFile.close()

      for command in commands:
        tmpFile.writeLine(command)
      tmpFile.flushFile()

      let editor = getEnv("EDITOR", "nano")
      discard execShellCmd(&"{editor} {tmpPath}")

      commands = @[]

      let strm = newFileStream(tmpPath)
      defer: strm.close()

      var line: string
      while strm.readLine(line):
        commands.add(line)

      removeFile(tmpPath)
      break
    else: discard

  for command in commands:
    discard os.execShellCmd(command)

proc writeHelp() =
  echo """
Splim - Slice album mp3 file into individual songs

Usage:
  splim [options] [-t=timestamps_file] [-i=input_file] [-o=output_directory]

Options:
  -t | --timestamps : timestamp file
  -i | --input      : album audio file
  -o | --output     : output directory
  -h | --help       : show help
  """

proc main() =
  var
    input, output, timestamps: string = ""

  if paramCount() == 0:
    writeHelp()
    quit()

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "timestamps", "t": timestamps = val
      of "input", "i": input = val
      of "output", "o": output = val
      of "help", "h":
        writeHelp()
        quit()
      else: discard
    else: discard

  if input == "":
    echo "Make sure to provide an input file"
    quit(1)
  if output == "":
    echo "Make sure to provide an output file"
    quit(1)
  if timestamps == "":
    echo "Make sure to provide a timestamps file"
    quit(1)

  splim(input, output, parseTimestamps(timestamps))

when isMainModule:
  main()