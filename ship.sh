#!/bin/bash

FOLDER=releases/sloubi-chess-alpha-0.0.1/

mkdir -p $FOLDER

jai src/first.jai -- release
cp bin/sloubi-chess $FOLDER/

mkdir -p $FOLDER/lib
cp lava/bindings/Shaderc/libshaderc.so $FOLDER/lib/
cp lava/bindings/StbTrueType/libstbtruetype.so $FOLDER/lib/
cp lava/bindings/Xcb/libxcbglue.so $FOLDER/lib/

cp -R assets/ $FOLDER/

