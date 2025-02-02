import macros, strutils

type
  Progmem*[T] {.byref.} = distinct T
  ProgmemString*[size: static[int]] = Progmem[array[size, char]]

{.push nodecl, header: "<avr/pgmspace.h>".}
proc pgmReadByte*[T](address: ptr T): uint8 {.importc: "pgm_read_byte".}
proc pgmReadWord*[T](address: ptr T): uint16 {.importc: "pgm_read_word".}
proc pgmReadDoubleWord*[T](address: ptr T): uint32 {.importc: "pgm_read_dword".}
proc memcpyPgm*[T](dest: ptr T, src: ptr T, size: csize_t): ptr T {.importc: "memcpy_P".}
{.pop.}

proc `[]`*[T](src: ptr Progmem[T]): T {.noinit.} =
    when sizeof(T) == 1:
      result = cast[T](pgmReadByte(cast[ptr T](src)))
    elif sizeof(T) == 2:
      result = cast[T]( pgmReadWord(cast[ptr T](src)))
    elif sizeof(T) == 4:
      result = cast[T](pgmReadDoubleWord(cast[ptr T](src)))
    else:
      discard memcpyPgm(result.addr, cast[ptr T](src), sizeof(T).csize_t)

proc readInto*[T](dst: var T, src: Progmem[T]) =
    when sizeof(T) == 1:
      dst = cast[T](pgmReadByte(cast[ptr T](src.unsafeAddr)))
    elif sizeof(T) == 2:
      dst = cast[T]( pgmReadWord(cast[ptr T](src.unsafeAddr)))
    elif sizeof(T) == 4:
      dst = cast[T](pgmReadDoubleWord(cast[ptr T](src.unsafeAddr)))
    else:
      discard memcpyPgm(dst.addr, cast[ptr T](src.unsafeAddr), sizeof(T).csize_t)

template read*[T](data: Progmem[T]): T =
  cast[T](
    when sizeof(T) == 1:
      pgmReadByte(cast[ptr T](data.unsafeAddr))
    elif sizeof(T) == 2:
      pgmReadWord(cast[ptr T](data.unsafeAddr))
    elif sizeof(T) == 4:
      pgmReadDoubleWord(cast[ptr T](data.unsafeAddr))
    else:
      var x {.noInit.} : T
      discard memcpyPgm(x.addr, cast[ptr T](data.unsafeAddr), sizeof(T).csize_t)
      x
  )

template len*[N, T](data: Progmem[array[N, T]]): untyped =
  array[N, T](data).len

template `[]`*[N, T](data: Progmem[array[N, T]], idx: int): untyped =
  when T isnot object:
    read(Progmem(array[N, T](data)[idx]))
  else:
    Progmem(array[N, T](data)[idx])

template `[]`*(data: Progmem[cstring], idx: int): untyped =
  pgmReadByte(cast[ptr char](cast[int](data) + idx)).char

import strutils

template p*(x: static[string]): untyped =
  # TODO: Look at unescape, C size must match Nim size, but x is a raw string..
  var data {.codegendecl: "", noinit.}: ProgmemString[unescape(x).len]
  {.emit:["static const char ", data, "[] PROGMEM = (\"", x, "\");"].}
  data

macro createFieldReaders*(obj: typed): untyped =
  let impl = getImpl(obj)
  doAssert(impl.kind == nnkTypeDef)
  doAssert(impl[2].kind == nnkObjectTy)
  result = newStmtList()
  for def in impl[2][2]:
    let
      name = def[0]
      kind = def[1]
    result.add quote do:
      template `name`(x: Progmem[`obj`]): `kind` =
        cast[`kind`](
          when sizeof(`kind`) == 1:
            pgmReadByte(cast[ptr uint8](cast[int](x.unsafeAddr) + `obj`.offsetof(`name`)))
          elif sizeof(`kind`) == 2:
            pgmReadWord(cast[ptr uint16](cast[int](x.unsafeAddr) + `obj`.offsetof(`name`)))
          elif sizeof(`kind`) == 4:
            pgmReadDoubleWord(cast[ptr uint32](cast[int](x.unsafeAddr) + `obj`.offsetof(`name`)))
          else:
            var x {.noInit.} : T
            discard memcpyPgm(x.addr, cast[ptr T](data.unsafeAddr), sizeof(T).csize_t)[]
            x
          )

macro progmem*(definitions: untyped): untyped =
  #echo definitions.treeRepr
  result = newStmtList()
  for definition in definitions:
    var
      hiddenName: NimNode
      name: NimNode
      data: NimNode
      dataType = newIdentNode("auto")
    case definition.kind:
    of nnkAsgn:
      hiddenName = genSym(nskLet, definition[0].strVal)
      name = definition[0]
      data = definition[1]
    of nnkCall:
      hiddenName = genSym(nskLet, definition[0].strVal)
      name = definition[0]
      dataType = definition[1][0][0]
      data = definition[1][0][1]
    else: discard
    result.add quote do:
      # Stupid workaround for https://github.com/nim-lang/Nim/issues/17497
      # const instead of NIM_CONST because of C++
      let `hiddenName` {.codegenDecl: "N_LIB_PRIVATE const $# PROGMEM $#".}: `dataType` = `data`
      template `name`*(): untyped = Progmem(`hiddenName`)
  echo result.repr
