# 用 JDK 17 干净编译并启动后端（避免 IDEA 混用 JDK 21/24）
$ErrorActionPreference = 'Stop'
$jdk17 = 'C:\Users\jzy05\.jdks\ms-17.0.16'
if (-not (Test-Path "$jdk17\bin\java.exe")) {
  Write-Error "找不到 JDK17: $jdk17"
}
$env:JAVA_HOME = $jdk17
$env:Path = "$jdk17\bin;" + $env:Path
Set-Location $PSScriptRoot
Write-Host "JAVA_HOME=$env:JAVA_HOME"
java -version
mvn -q clean spring-boot:run "-Dspring-boot.run.profiles=local"
