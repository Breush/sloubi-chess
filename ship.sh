#!/bin/bash

## @fixme Better write that in JAI!

### Increments the part of the string
## $1: version itself in form XXX-MAJOR.MINOR.PATCH
## $2: number of part: 0 – major, 1 – minor, 2 – patch
increment_version() {
    local parts=($(echo "$1" | tr - '\n'))
    local array=($(echo "${parts[1]}" | tr . '\n'))

    for index in ${!array[@]}; do
        if [ $index -eq $2 ]; then
            local value=array[$index]
            value=$((value+1))
            array[$index]=$value
            break
        fi
    done

    echo $(IFS=. ; echo "${parts[0]}-${array[*]}")
}

git fetch --tags
OLD_VERSION=$(git tag | tail -n 1)
VERSION=$(increment_version $OLD_VERSION 2)

echo "Releasing $VERSION"

if [[ "$OSTYPE" == "msys" ]]; then
    FOLDER=releases/sloubi-chess-$VERSION-win64
else
    FOLDER=releases/sloubi-chess-$VERSION-linux64
fi

rm -rf $FOLDER
mkdir -p $FOLDER

jai src/first.jai -- release

if [[ "$OSTYPE" == "msys" ]]; then
    cp bin/sloubi-chess.exe $FOLDER/

    cp lava/bindings/Shaderc/libshaderc.dll $FOLDER/
    cp lava/bindings/StbTrueType/libstbtruetype.dll $FOLDER/
    cp lava/bindings/Vulkan/libvulkan.dll $FOLDER/
else
    cp bin/sloubi-chess $FOLDER/

    mkdir -p $FOLDER/lib
    cp lava/bindings/Shaderc/libshaderc.so $FOLDER/lib/
    cp lava/bindings/StbTrueType/libstbtruetype.so $FOLDER/lib/
    cp lava/bindings/Xcb/libxcbglue.so $FOLDER/lib/
fi

cp -R assets/ $FOLDER/
