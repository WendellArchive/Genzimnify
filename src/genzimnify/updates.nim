## Optional release checks. No installer is ever executed by the CLI.
import std/[os, osproc, streams, strutils, json]
import version

const ReleasesUrl* = "https://github.com/Obliv1onis/Genzimnify/releases/latest"
const LatestApi = "https://api.github.com/repos/Obliv1onis/Genzimnify/releases/latest"
const InstallerBase = "https://raw.githubusercontent.com/Obliv1onis/Genzimnify/master/scripts/install."

proc stableVersion(value: string): seq[int] =
  let clean = if value.startsWith("v"): value[1 .. ^1] else: value
  let parts = clean.split('.')
  if parts.len != 3: return
  for part in parts:
    if part.len == 0 or part.len > 9: return @[]
    for ch in part:
      if ch notin {'0'..'9'}: return @[]
    result.add parseInt(part)

proc newerVersion*(candidate, current: string): bool =
  let a = stableVersion(candidate)
  let b = stableVersion(current)
  if a.len != 3 or b.len != 3: return false
  for i in 0..2:
    if a[i] != b[i]: return a[i] > b[i]

proc updateInstructions*(): string =
  result = "Latest release: " & ReleasesUrl & "\n"
  let executable = getAppFilename().replace('\\', '/')
  if "/Cellar/" in executable or "/homebrew/" in executable:
    result.add "Homebrew install: brew update && brew upgrade --fetch-HEAD genzimnify\n"
  else:
    when defined(windows):
      result.add "PowerShell installer: irm " & InstallerBase & "ps1 | iex\n"
    elif (defined(macosx) and defined(arm64)) or (defined(linux) and defined(amd64)):
      result.add "Shell installer: curl -fsSL " & InstallerBase & "sh | sh\n"
    else:
      result.add "This platform has no current prebuilt installer; build the latest source release.\n"
  result.add "For a custom install location, set GZIM_INSTALL_ROOT to that directory before installing.\n"
  result.add "Source builds: update your checkout, then run nimble build -d:release.\n"
  result.add "After updating, run gzim doctor to verify the executable path, then gzim --version."

proc latestStable(): string =
  let curl = findExe("curl")
  if curl == "": return
  # curl owns the HTTPS implementation; avoid adding an OpenSSL runtime dependency.
  # Disable user curl config and bound transfer time and output size.
  let process = startProcess(curl, args = @["--disable", "--fail", "--silent",
    "--connect-timeout", "1", "--max-time", "2", "--max-filesize", "65536",
    "--user-agent", "gzim/" & GenzimnifyVersion,
    "--header", "Accept: application/vnd.github+json", LatestApi],
    options = {poStdErrToStdOut})
  defer: process.close()
  let output = process.outputStream.readAll()
  if process.waitForExit() != 0: return
  let release = parseJson(output)
  if release.kind != JObject or release{"draft"}.getBool() or release{"prerelease"}.getBool(): return
  let tag = release{"tag_name"}.getStr()
  if stableVersion(tag).len == 3: result = tag

proc showUpdateNotice*() =
  if getEnv("GZIM_NO_UPDATE_CHECK") == "1": return
  try:
    let latest = latestStable()
    if latest == "":
      stderr.writeLine("Update check unavailable; latest releases: " & ReleasesUrl)
    elif newerVersion(latest, GenzimnifyVersion):
      stderr.writeLine("Update available: " & GenzimnifyVersion & " -> " & latest)
      stderr.writeLine(updateInstructions())
  except CatchableError:
    stderr.writeLine("Update check unavailable; latest releases: " & ReleasesUrl)
