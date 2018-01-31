@echo off
REM call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvarsall.bat" x86
call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
cl /I..\..\hashlink\src /I..\godot_headers /c main.c
cl /I..\..\hashlink\src /c ..\..\hashlink\src\code.c
cl /I..\..\hashlink\src /c ..\..\hashlink\src\module.c
cl /I..\..\hashlink\src /c ..\..\hashlink\src\jit.c
link /DLL /OUT:..\project\hlgodot_entry.dll *.obj ..\..\hashlink\Release\libhl.lib user32.lib
