## Lightweight project manifest and Git/path package manager for gzim.

import std/[algorithm, json, os, osproc, streams, strutils, syncio, tables]

const ManifestName* = "gzim.toml"

type
  PackageError* = object of CatchableError
  Manifest* = object
    name*: string
    version*: string
    dependencies*: OrderedTable[string, string]

proc cleanQuoted(value: string): string =
  result = value.strip()
  if result.len >= 2 and result[0] == '"' and result[^1] == '"':
    result = result[1 .. ^2]

proc loadManifest*(root: string): Manifest =
  result.name = lastPathPart(root)
  result.version = "0.1.0"
  result.dependencies = initOrderedTable[string, string]()
  let path = root / ManifestName
  if not fileExists(path):
    raise newException(PackageError, "no gzim.toml here; run 'gzim init' first")
  var section = ""
  for rawLine in lines(path):
    let line = rawLine.strip()
    if line == "" or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      section = line[1 .. ^2]
      continue
    let separator = line.find('=')
    if separator < 1: continue
    let key = line[0 ..< separator].strip()
    let value = cleanQuoted(line[separator + 1 .. ^1])
    case section
    of "project":
      if key == "name": result.name = value
      elif key == "version": result.version = value
    of "dependencies": result.dependencies[key] = value
    else: discard

proc saveManifest*(manifest: Manifest, root: string) =
  var names: seq[string]
  for name in manifest.dependencies.keys: names.add name
  names.sort()
  var output = "[project]\nname = \"" & manifest.name & "\"\nversion = \"" & manifest.version & "\"\n\n[dependencies]\n"
  for name in names:
    output.add name & " = \"" & manifest.dependencies[name] & "\"\n"
  writeFile(root / ManifestName, output)

proc initManifest*(root: string) =
  if fileExists(root / ManifestName): return
  var manifest = Manifest(name: lastPathPart(absolutePath(root)), version: "0.1.0",
    dependencies: initOrderedTable[string, string]())
  manifest.saveManifest(root)

proc validPackageName(name: string): bool =
  if name == "": return false
  for ch in name:
    if not (ch.isAlphaNumeric or ch in {'-', '_'}): return false
  true

proc runGit(args: seq[string], root: string): string =
  let git = findExe("git")
  if git == "": raise newException(PackageError, "git is required to install Git dependencies")
  let process = startProcess(git, workingDir = root, args = args,
    options = {poUsePath, poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let code = process.waitForExit()
  process.close()
  if code != 0: raise newException(PackageError, output.strip())
  output.strip()

proc packageRoot*(root: string): string = root / ".gzim" / "packages"

proc loadLock(root: string): Table[string, tuple[source, revision: string]] =
  result = initTable[string, tuple[source, revision: string]]()
  let path = root / "gzim.lock"
  if not fileExists(path): return
  try:
    let document = parseFile(path)
    if document.hasKey("packages"):
      for name, item in document["packages"]:
        result[name] = (item{"source"}.getStr(""), item{"revision"}.getStr(""))
  except CatchableError:
    raise newException(PackageError, "gzim.lock is invalid; delete it and run 'gzim install'")

proc saveLock(root: string, entries: Table[string, tuple[source, revision: string]]) =
  var packages = newJObject()
  var names: seq[string]
  for name in entries.keys: names.add name
  names.sort()
  for name in names:
    packages[name] = %*{"source": entries[name].source, "revision": entries[name].revision}
  let path = root / "gzim.lock"
  let temporary = path & ".tmp-" & $getCurrentProcessId()
  try:
    writeFile(temporary, pretty(%*{"version": 1, "packages": packages}) & "\n")
    moveFile(temporary, path)
  finally:
    if fileExists(temporary): removeFile(temporary)

proc fetchPackage(root, destination, source: string, lockedRevision = ""): string =
  var localSource = source
  if localSource.startsWith("path:"): localSource = localSource[5 .. ^1]
  if localSource == "": raise newException(PackageError, "package source cannot be empty")
  let resolvedLocal = if localSource.isAbsolute: localSource else: root / localSource
  if dirExists(resolvedLocal):
    copyDir(expandFilename(resolvedLocal), destination)
    return "path"

  var url = source
  var reference = ""
  let hashAt = source.rfind('#')
  if hashAt > source.find("://") + 2:
    url = source[0 ..< hashAt]
    reference = source[hashAt + 1 .. ^1]
  if lockedRevision != "": reference = lockedRevision
  if reference == "":
    discard runGit(@["clone", "--depth", "1", url, destination], root)
  else:
    createDir(destination)
    discard runGit(@["-C", destination, "init"], root)
    discard runGit(@["-C", destination, "remote", "add", "origin", url], root)
    discard runGit(@["-C", destination, "fetch", "--depth", "1", "origin", reference], root)
    discard runGit(@["-C", destination, "checkout", "--detach", "FETCH_HEAD"], root)
  runGit(@["-C", destination, "rev-parse", "HEAD"], root)

proc validateSource(root, name, source: string) =
  if not validPackageName(name):
    raise newException(PackageError, "invalid package name '" & name & "'")
  let packages = packageRoot(root)
  createDir(packages)
  var localSource = source
  if localSource.startsWith("path:"): localSource = localSource[5 .. ^1]
  if localSource == "": raise newException(PackageError, "package source cannot be empty")
  let resolvedLocal = if localSource.isAbsolute: localSource else: root / localSource
  if dirExists(resolvedLocal):
    let canonicalSource = expandFilename(resolvedLocal)
    let canonicalRoot = expandFilename(root)
    let canonicalPackages = expandFilename(packages)
    if canonicalSource == canonicalRoot or canonicalRoot.startsWith(canonicalSource & $DirSep) or
        canonicalSource == canonicalPackages or canonicalSource.startsWith(canonicalPackages & $DirSep) or
        canonicalPackages.startsWith(canonicalSource & $DirSep):
      raise newException(PackageError, "package path must be outside the project package cache")

proc installDependencies*(root: string, locked = false, update = false, updateName = ""): int =
  let manifest = loadManifest(root)
  let oldLock = loadLock(root)
  if updateName != "" and not manifest.dependencies.hasKey(updateName):
    raise newException(PackageError, "package '" & updateName & "' is not in gzim.toml")
  if locked:
    if not fileExists(root / "gzim.lock"):
      raise newException(PackageError, "--locked requires gzim.lock; run 'gzim install' first")
    if oldLock.len != manifest.dependencies.len:
      raise newException(PackageError, "gzim.lock is out of date; run 'gzim install'")
    for name, source in manifest.dependencies:
      if not oldLock.hasKey(name) or oldLock[name].source != source or oldLock[name].revision == "":
        raise newException(PackageError, "gzim.lock is out of date for '" & name & "'")
  for name, source in manifest.dependencies: validateSource(root, name, source)
  let packages = packageRoot(root)
  let transaction = root / ".gzim" / (".install-" & $getCurrentProcessId())
  if dirExists(transaction):
    raise newException(PackageError, "unfinished package transaction: " & transaction)
  createDir(transaction)
  createDir(transaction / "incoming")
  createDir(transaction / "previous")
  var cleanup = true
  defer:
    if cleanup and dirExists(transaction): removeDir(transaction)
  var newLock = initTable[string, tuple[source, revision: string]]()
  # Resolve every dependency before replacing any installed package.
  for name, source in manifest.dependencies:
    stdout.writeLine("pulling up " & name & "...")
    let refresh = update and (updateName == "" or updateName == name)
    let pin = if not refresh and oldLock.hasKey(name) and oldLock[name].source == source:
      oldLock[name].revision else: ""
    let revision = fetchPackage(root, transaction / "incoming" / name, source, if pin == "path": "" else: pin)
    newLock[name] = (source, revision)
  var replaced, backedUp: seq[string]
  try:
    for name in manifest.dependencies.keys:
      let destination = packages / name
      if dirExists(destination):
        moveDir(destination, transaction / "previous" / name)
        backedUp.add name
      moveDir(transaction / "incoming" / name, destination)
      replaced.add name
    if not locked: saveLock(root, newLock)
  except CatchableError:
    try:
      for name in replaced:
        if dirExists(packages / name): removeDir(packages / name)
      for name in backedUp: moveDir(transaction / "previous" / name, packages / name)
    except CatchableError as rollbackError:
      cleanup = false
      raise newException(PackageError, "package rollback failed; preserved backups in " & transaction & ": " & rollbackError.msg)
    raise
  result = manifest.dependencies.len

proc addDependency*(root, name, source: string) =
  if not validPackageName(name):
    raise newException(PackageError, "invalid package name '" & name & "'")
  var manifest = loadManifest(root)
  let oldManifest = manifest
  manifest.dependencies[name] = source
  manifest.saveManifest(root)
  try:
    discard installDependencies(root)
  except CatchableError:
    oldManifest.saveManifest(root)
    raise

proc removeDependency*(root, name: string) =
  if not validPackageName(name):
    raise newException(PackageError, "invalid package name '" & name & "'")
  var manifest = loadManifest(root)
  if not manifest.dependencies.hasKey(name):
    raise newException(PackageError, "package '" & name & "' is not in gzim.toml")
  manifest.dependencies.del(name)
  manifest.saveManifest(root)
  let destination = packageRoot(root) / name
  if dirExists(destination): removeDir(destination)
  discard installDependencies(root)

proc findProjectRoot*(start: string): string =
  var current = absolutePath(start)
  if fileExists(current): current = parentDir(current)
  while true:
    if fileExists(current / ManifestName): return current
    let parent = parentDir(current)
    if parent == current: return ""
    current = parent
