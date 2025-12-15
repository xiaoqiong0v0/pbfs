# 报错误停止
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$workDir = ".\.lib\opencv"
if (!(Test-Path "$workDir"))
{
    New-Item -ItemType Directory -Force -Path "$workDir"
}
# 之后的目录相对应工作目录
$workDirAbs = (Resolve-Path $workDir).Path
Write-Host "Working directory: $workDirAbs"

$downloadPath = Join-Path "$workDirAbs" "download"
$dllPath = Join-Path "$workDirAbs" "dll"
$buildPath = Join-Path "$workDirAbs" "build"
$toolPath = Join-Path "$buildPath" "tool"
$sourcePath = Join-Path "$buildPath" "source"
$compilePath = Join-Path "$buildPath" "compile"

$mingwPath = Join-Path "$toolPath" "mingw"
$cmakePath = Join-Path "$toolPath" "cmake"
$zip7Path = Join-Path "$toolPath" "zip7"

$opencvPath = Join-Path "$sourcePath" "opencv"
$opencvContribPath = Join-Path "$sourcePath" "opencv_contrib"

# 下载路径
$zip7UrlBase = "https://raw.githubusercontent.com/xiaoqiong0v0/pbfs/refs/heads/main/7z2501-x64/"
$mingwUrl = "https://sf-west-interserver-1.dl.sourceforge.net/project/mingw-w64/Toolchains%20targetting%20Win64/Personal%20Builds/mingw-builds/8.1.0/threads-posix/seh/x86_64-8.1.0-release-posix-seh-rt_v6-rev0.7z?viasf=1"
$mingwFile = "x86_64-8.1.0-release-posix-seh-rt_v6-rev0.7z"
$cmakeUrl = "https://release-assets.githubusercontent.com/github-production-release-asset/537699/9e5bbe71-8b8f-4192-ba51-eeb4f3784de7?sp=r&sv=2018-11-09&sr=b&spr=https&se=2025-12-12T09%3A01%3A16Z&rscd=attachment%3B+filename%3Dcmake-4.2.1-windows-x86_64.zip&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2025-12-12T08%3A00%3A39Z&ske=2025-12-12T09%3A01%3A16Z&sks=b&skv=2018-11-09&sig=L3mxitR80CMx9Gc78eToMtmBswRhZuF8sn7CO8R0aUc%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc2NTUyODkyMywibmJmIjoxNzY1NTI3MTIzLCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ._247Sbj1sZ-TaZo6dnhKDNDyUJjmz2l7o2djGX0kWYQ&response-content-disposition=attachment%3B%20filename%3Dcmake-4.2.1-windows-x86_64.zip&response-content-type=application%2Foctet-stream"
$cmakeFile = "cmake-4.2.1-windows-x86_64.zip"
$opencvUrl = "https://github.com/opencv/opencv/archive/4.12.0.zip"
$opencvFile = "opencv-4.12.0.zip"
$opencvContribUrl = "https://github.com/opencv/opencv_contrib/archive/4.12.0.zip"
$opencvContribFile = "opencv_contrib-4.12.0.zip"

#### 工具方法区域 不会使用全局变量
# 检查目录
function CheckDir
{
    param(
        [string]$dir
    )
    if (!(Test-Path "$dir"))
    {
        New-Item -ItemType Directory -Force -Path "$dir"
    }
}

# 多个路径拼接
function PathJoin
{
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Root,
        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [string[]]$Segments
    )
    $Segments | ForEach-Object { $Root = Join-Path "$Root" "$_" }
    return $Root
}

# 解压exe
function DecompressExe
{
    param(
        [string]$exePath,
        [string]$distDir
    )
    $shell = New-Object -ComObject Shell.Application
    $shell.Namespace($distDir).CopyHere($shell.Namespace($exePath).Items(), 0x400)
}

# 检查代理
function CheckProxy
{
    $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxy = $reg.ProxyServer
    $enable = $reg.ProxyEnable -eq 1
    if ($enable)
    {
        Write-Host "Proxy detected: $proxy"
        # 设置 WebRequest 代理
        [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy -Property @{
            Address = "http://$proxy"
            UseDefaultCredentials = $true
        }
        # 同时设置环境变量
        $env:HTTP_PROXY = "http://$proxy"
        $env:HTTPS_PROXY = "http://$proxy"
        $env:http_proxy = "http://$proxy"
        $env:https_proxy = "http://$proxy"
        $env:NO_PROXY = "localhost,127.0.0.1,*.local"
        $env:no_proxy = "localhost,127.0.0.1,*.local"
    }
}

#### 业务方法区域

# 下载 7zip 用于解压
function Check7Zip()
{
    if (!(Test-Path "$zip7Path"))
    {
        CheckDir "$zip7Path"
    }
    $dllPath = PathJoin "$zip7Path" "7z.dll"
    if (!(Test-Path "$dllPath"))
    {
        Write-Host "Downloading 7z.dll"
        try
        {
            Invoke-WebRequest -Uri "$zip7UrlBase/7z.dll" -OutFile "$dllPath"
        }
        catch
        {
            # 删除文件
            Remove-Item "$dllPath" -Force -ErrorAction SilentlyContinue
            throw
        }
    }
    $exePath = PathJoin "$zip7Path" "7z.exe"
    if (!(Test-Path "$exePath"))
    {
        Write-Host "Downloading 7z.exe"
        try
        {
            Invoke-WebRequest -Uri "$zip7UrlBase/7z.exe" -OutFile "$exePath"
        }
        catch
        {
            # 删除文件
            Remove-Item "$exePath" -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

# 检查文件 并下载
function CheckFileDownload
{
    param(
        [string]$url,
        [string]$fileName
    )
    $dstPath = Join-Path "$downloadPath" "$fileName"
    if (!(Test-Path "$dstPath"))
    {
        Write-Host "Downloading: $url"
        Write-Host "Saving to: $dstPath"
        try
        {
            Invoke-WebRequest -Uri "$url" -OutFile "$dstPath"
        }
        catch
        {
            # 失败删除 文件
            Remove-Item "$dstPath" -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

# 检查 解压下载的文件
function CheckExtractDownloadFile
{
    param(
        [string]$fileName,
        [string]$distDir
    )
    $srcPath = Join-Path "$downloadPath" "$fileName"
    if (!(Test-Path "$distDir"))
    {
        Write-Host "Extracting: $srcPath"
        Write-Host "Saving to: $distDir"
        #  使用 7zip
        $exePath = Join-Path "$zip7Path" "7z.exe"
        try
        {
            & "$exePath" x "$srcPath" "-o$distDir" -spe
            # 如果目录下面出现单个目录 往上移动后删除该目录
            $files = Get-ChildItem -Path "$distDir" -Name
            if ($files.Count -eq 1)
            {
                $childDir = Join-Path "$distDir" "$( $files | Select-Object -First 1 )"
                # 必需是目录才遍历
                if (Test-Path -PathType Container "$childDir")
                {
                    Get-ChildItem -Path "$childDir" | Move-Item -Destination "$distDir"
                    Remove-Item "$childDir" -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch
        {
            # 删除文件
            Remove-Item "$srcPath" -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

CheckDir "$downloadPath"
CheckDir "$buildPath"
CheckDir "$sourcePath"
CheckDir "$toolPath"

CheckProxy
# 检查文件并下载
CheckFileDownload "$mingwUrl" "$mingwFile"
CheckFileDownload "$cmakeUrl" "$cmakeFile"
CheckFileDownload "$opencvUrl" "$opencvFile"
CheckFileDownload "$opencvContribUrl" "$opencvContribFile"

# 检查解压文件
Check7Zip
CheckExtractDownloadFile "$mingwFile" "$mingwPath"
CheckExtractDownloadFile "$cmakeFile" "$cmakePath"
CheckExtractDownloadFile "$opencvFile" "$opencvPath"
CheckExtractDownloadFile "$opencvContribFile" "$opencvContribPath"

Write-Host "Mingw path: $mingwPath"
Write-Host "Cmake path: $cmakePath"

# 把工具bin添加到PATH
$env:Path = "$mingwPath\bin;$cmakePath\bin"

$currentPath = Get-Location
Write-Host "Goto compile path: $compilePath"
Set-Location "$compilePath"
# 清空目录防止旧文件干扰
if ($1 -eq "clean")
{
    Remove-Item -Recurse -Force "$compilePath\*" -ErrorAction SilentlyContinue
}
# cmake C:\opencv\opencv-4.12.0
# -G "MinGW Makefiles"
# -BC:\opencv\build
# -DENABLE_CXX11=ON
# -DOPENCV_EXTRA_MODULES_PATH=C:\opencv\opencv_contrib-4.12.0\modules
# -DBUILD_SHARED_LIBS=%enable_shared%
# -DWITH_IPP=OFF
# -DWITH_MSMF=OFF
# -DBUILD_EXAMPLES=OFF
# -DBUILD_TESTS=OFF
# -DBUILD_PERF_TESTS=ON
# -DBUILD_opencv_java=OFF
# -DBUILD_opencv_python=OFF
# -DBUILD_opencv_python2=OFF
# -DBUILD_opencv_python3=OFF
# -DBUILD_DOCS=OFF
# -DENABLE_PRECOMPILED_HEADERS=OFF
# -DBUILD_opencv_saliency=OFF
# -DBUILD_opencv_wechat_qrcode=ON
# -DCPU_DISPATCH=
# -DOPENCV_GENERATE_PKGCONFIG=ON
# -DWITH_OPENCL_D3D11_NV=OFF
# -DOPENCV_ALLOCATOR_STATS_COUNTER_TYPE=int64_t
# -Wno-dev
try
{
    cmake "$opencvPath" `
    -G "MinGW Makefiles" `
    "-B$compilePath" `
    "-DCMAKE_INSTALL_PREFIX=$dllPath" `
    -DENABLE_CXX11=ON `
    "-DOPENCV_EXTRA_MODULES_PATH=$opencvContribPath\modules" `
    -DBUILD_SHARED_LIBS=ON `
    -DWITH_IPP=OFF `
    -DWITH_MSMF=OFF `
    -DBUILD_EXAMPLES=OFF `
    -DBUILD_TESTS=OFF `
    -DBUILD_PERF_TESTS=ON `
    -DBUILD_opencv_java=OFF `
    -DBUILD_opencv_python=OFF `
    -DBUILD_opencv_python2=OFF `
    -DBUILD_opencv_python3=OFF `
    -DBUILD_DOCS=OFF `
    -DENABLE_PRECOMPILED_HEADERS=OFF `
    -DBUILD_opencv_saliency=OFF `
    -DBUILD_opencv_wechat_qrcode=ON `
    -DCPU_DISPATCH= `
    -DOPENCV_GENERATE_PKGCONFIG=ON `
    -DWITH_OPENCL_D3D11_NV=OFF `
    -DOPENCV_ALLOCATOR_STATS_COUNTER_TYPE=int64_t `
    -Wno-dev

    # 编译
    mingw32-make "-j$( $env:NUMBER_OF_PROCESSORS )"
    # 安装
    mingw32-make install

    Write-Host "env:"
    @"
Path=`$PROJECT_DIR$\.lib\opencv\build\tool\cmake\bin;`$PROJECT_DIR$\.lib\opencv\build\tool\mingw\bin;`$PROJECT_DIR$\.lib\opencv\dll\x64\mingw\bin;`${GOROOT}\bin
CC=gcc
CXX=g++
CGO_CXXFLAGS=--std=c++11
CGO_CPPFLAGS=-I`$PROJECT_DIR$\.lib\opencv\dll\include
CGO_LDFLAGS=-L`$PROJECT_DIR$\.lib\opencv\dll\x64\mingw\lib -lopencv_core4120 -lopencv_face4120 -lopencv_videoio4120 -lopencv_imgproc4120 -lopencv_highgui4120 -lopencv_imgcodecs4120 -lopencv_objdetect4120 -lopencv_features2d4120 -lopencv_video4120 -lopencv_dnn4120 -lopencv_xfeatures2d4120 -lopencv_plot4120 -lopencv_tracking4120 -lopencv_img_hash4120 -lopencv_calib3d4120
"@
}
finally
{
    Set-Location $currentPath
}
