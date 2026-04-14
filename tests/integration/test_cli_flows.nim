import std/[os, osproc, strtabs, strutils, times, unittest]
import ../../src/buddydrive/config as buddyconfig
import ../testutils

var cliBinaryPath {.global.}: string

proc repoRoot(): string =
  currentSourcePath().parentDir().parentDir().parentDir()

proc ensureCliBinary(): string =
  if cliBinaryPath.len == 0:
    cliBinaryPath = getTempDir() / ("buddydrive_test_cli_" & $getTime().toUnix())
    let build = execCmdEx(
      "nim c -o:" & quoteShell(cliBinaryPath) & " src/buddydrive.nim",
      workingDir = repoRoot()
    )
    doAssert build.exitCode == 0, build.output
  cliBinaryPath

proc cliEnv(testDir: string): StringTableRef =
  result = newStringTable()
  result["BUDDYDRIVE_CONFIG_DIR"] = testDir
  result["BUDDYDRIVE_DATA_DIR"] = testDir
  result["HOME"] = testDir

template withCliEnv(testDir: string, body: untyped): untyped =
  putEnv("BUDDYDRIVE_CONFIG_DIR", testDir)
  putEnv("BUDDYDRIVE_DATA_DIR", testDir)
  defer:
    delEnv("BUDDYDRIVE_CONFIG_DIR")
    delEnv("BUDDYDRIVE_DATA_DIR")
  body

suite "CLI flows":
  test "init creates config":
    withTestDir("cliinit"):
      let cli = ensureCliBinary()
      let result = execCmdEx(quoteShell(cli) & " init", env = cliEnv(testDir), workingDir = repoRoot())
      check result.exitCode == 0
      check result.output.contains("Config created at")
      check fileExists(testDir / "config.toml")

  test "add-buddy stores pairing code":
    withTestDir("cliaddbuddy"):
      let cli = ensureCliBinary()
      discard execCmdEx(quoteShell(cli) & " init", env = cliEnv(testDir), workingDir = repoRoot())
      let result = execCmdEx(
        quoteShell(cli) & " add-buddy --id buddy-1 --code swift-eagle",
        env = cliEnv(testDir),
        workingDir = repoRoot()
      )
      check result.exitCode == 0
      withCliEnv(testDir):
        let cfg = buddyconfig.loadConfig()
        check cfg.buddies.len == 1
        check cfg.buddies[0].id.uuid == "buddy-1"
        check cfg.buddies[0].pairingCode == "swift-eagle"

  test "add-folder and config set append-only persist":
    withTestDir("clifoldercfg"):
      let cli = ensureCliBinary()
      let folderPath = testDir / "docs"
      createDir(folderPath)
      discard execCmdEx(quoteShell(cli) & " init", env = cliEnv(testDir), workingDir = repoRoot())
      let addResult = execCmdEx(
        quoteShell(cli) & " add-folder " & quoteShell(folderPath) & " --name docs",
        env = cliEnv(testDir),
        workingDir = repoRoot()
      )
      check addResult.exitCode == 0

      let cfgResult = execCmdEx(
        quoteShell(cli) & " config set folder-append-only docs on",
        env = cliEnv(testDir),
        workingDir = repoRoot()
      )
      check cfgResult.exitCode == 0

      withCliEnv(testDir):
        let cfg = buddyconfig.loadConfig()
        check cfg.folders.len == 1
        check cfg.folders[0].name == "docs"
        check cfg.folders[0].appendOnly

  test "sync-config reports recovery not enabled":
    withTestDir("clisyncconfig"):
      let cli = ensureCliBinary()
      discard execCmdEx(quoteShell(cli) & " init", env = cliEnv(testDir), workingDir = repoRoot())
      let result = execCmdEx(quoteShell(cli) & " sync-config", env = cliEnv(testDir), workingDir = repoRoot())
      check result.exitCode == 0
      check result.output.contains("Recovery not enabled")

  test "recover rejects invalid mnemonic":
    withTestDir("clirecoverinvalid"):
      let cli = ensureCliBinary()
      let result = execCmdEx(
        quoteShell(cli) & " recover",
        env = cliEnv(testDir),
        workingDir = repoRoot(),
        input = "not a valid mnemonic\n"
      )
      check result.exitCode == 0
      check result.output.contains("Invalid recovery phrase")

  test "export-recovery reports recovery not enabled":
    withTestDir("cliexportrecovery"):
      let cli = ensureCliBinary()
      discard execCmdEx(quoteShell(cli) & " init", env = cliEnv(testDir), workingDir = repoRoot())
      let result = execCmdEx(quoteShell(cli) & " export-recovery", env = cliEnv(testDir), workingDir = repoRoot())
      check result.exitCode == 0
      check result.output.contains("Recovery not enabled")
