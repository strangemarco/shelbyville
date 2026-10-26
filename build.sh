#!/bin/sh
set -e

echo "=== 1. Instalando SDK de .NET 10.0 ==="
curl -sSL https://dot.net/v1/dotnet-install.sh > dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh -c 10.0 -InstallDir ./dotnet

export PATH="$(pwd)/dotnet:$PATH"
export DOTNET_ROOT="$(pwd)/dotnet"

echo "=== 2. Version de .NET instalada ==="
dotnet --version

echo "=== 3. Publicando Blazor WebAssembly en Release ==="
dotnet publish Shelbyville/Shelbyville.csproj -c Release -o output

echo "=== 4. Publicacion finalizada con exito en output/wwwroot ==="
