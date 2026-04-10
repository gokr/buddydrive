import std/times
import results
import chronos
import libp2p
import libp2p/stream/bufferstream

export results

type
  MessageKind* = enum
    msgFileList
    msgFileRequest
    msgFileData
    msgFileAck
    msgFileDelete
    msgPing
    msgPong
    msgSyncDone

  CompressionKind* = enum
    ckNone = 0
    ckLz4 = 1

  ProtocolMessage* = object
    case kind*: MessageKind
    of msgFileList:
      folderName*: string
      files*: seq[FileEntry]
    of msgFileRequest:
      requestPath*: string
      requestOffset*: int64
      requestLength*: int
    of msgFileData:
      data*: seq[byte]
      dataOffset*: int64
      totalSize*: int64
      done*: bool
      dataCompression*: CompressionKind
      dataOriginalLen*: int
    of msgFileAck:
      success*: bool
      bytesReceived*: int64
    of msgFileDelete:
      deletedPath*: string
    of msgPing:
      timestamp*: int64
    of msgPong:
      pingTimestamp*: int64
    of msgSyncDone:
      syncFolderName*: string
  
  FileEntry* = object
    path*: string
    size*: int64
    mtime*: int64
    hash*: string

const
  ProtocolVersion*: uint8 = 2
  MaxMessageSize*: int = 1024 * 1024 * 10  # 10MB max
  ChunkSize*: int = 64 * 1024  # 64KB chunks

proc encodeInt*[T: SomeInteger](val: T): seq[byte] =
  when T is int64:
    result = @[
      byte(val shr 56),
      byte(val shr 48),
      byte(val shr 40),
      byte(val shr 32),
      byte(val shr 24),
      byte(val shr 16),
      byte(val shr 8),
      byte(val)
    ]
  elif T is int32 or T is uint32:
    result = @[
      byte(val shr 24),
      byte(val shr 16),
      byte(val shr 8),
      byte(val)
    ]
  else:
    result = @[byte(val)]

proc readInt64*(data: seq[byte], offset: int): int64 =
  result = int64(data[offset]) shl 56 or
           int64(data[offset+1]) shl 48 or
           int64(data[offset+2]) shl 40 or
           int64(data[offset+3]) shl 32 or
           int64(data[offset+4]) shl 24 or
           int64(data[offset+5]) shl 16 or
           int64(data[offset+6]) shl 8 or
           int64(data[offset+7])

proc readUint32*(data: seq[byte], offset: int): uint32 =
  result = uint32(data[offset]) shl 24 or
           uint32(data[offset+1]) shl 16 or
           uint32(data[offset+2]) shl 8 or
           uint32(data[offset+3])

proc encode*(msg: ProtocolMessage): seq[byte] =
  result = @[]
  result.add(byte(msg.kind))
  result.add(ProtocolVersion)
  
  case msg.kind
  of msgFileList:
    result.add(msg.folderName.len.byte)
    result.add(msg.folderName.toOpenArrayByte(0, msg.folderName.len-1))
    result.add(msg.files.len.uint32.encodeInt())
    for f in msg.files:
      result.add(f.path.len.byte)
      result.add(f.path.toOpenArrayByte(0, f.path.len-1))
      result.add(f.size.encodeInt())
      result.add(f.mtime.encodeInt())
      result.add(f.hash.len.byte)
      result.add(f.hash.toOpenArrayByte(0, f.hash.len-1))
  
  of msgFileRequest:
    result.add(msg.requestPath.len.byte)
    result.add(msg.requestPath.toOpenArrayByte(0, msg.requestPath.len-1))
    result.add(msg.requestOffset.encodeInt())
    result.add(msg.requestLength.int32.encodeInt())
  
  of msgFileData:
    result.add(msg.dataOffset.encodeInt())
    result.add(msg.totalSize.encodeInt())
    result.add(msg.done.byte)
    result.add(byte(msg.dataCompression))
    result.add(msg.dataOriginalLen.uint32.encodeInt())
    result.add(msg.data.len.uint32.encodeInt())
    result.add(msg.data)
  
  of msgFileAck:
    result.add(msg.success.byte)
    result.add(msg.bytesReceived.encodeInt())
  
  of msgFileDelete:
    result.add(msg.deletedPath.len.byte)
    result.add(msg.deletedPath.toOpenArrayByte(0, msg.deletedPath.len-1))
  
  of msgPing:
    result.add(msg.timestamp.encodeInt())
  
  of msgPong:
    result.add(msg.pingTimestamp.encodeInt())

  of msgSyncDone:
    discard

proc decode*(data: seq[byte]): Result[ProtocolMessage, string] =
  if data.len < 2:
    return err("Message too short")
  
  let kindByte = data[0]
  if kindByte > ord(msgSyncDone):
    return err("Invalid message kind: " & $kindByte)
  
  let kind = MessageKind(kindByte)
  let version = data[1]
  
  if version != ProtocolVersion:
    return err("Unsupported protocol version")
  
  var msg = ProtocolMessage(kind: kind)
  
  var pos = 2
  
  template checkLen(n: int) =
    if pos + n > data.len:
      return err("Message truncated at pos " & $pos & ", need " & $n & " bytes")
  
  case kind
  of msgFileList:
    checkLen(1)
    let nameLen = int(data[pos])
    pos += 1
    
    checkLen(nameLen)
    msg.folderName = newString(nameLen)
    for i in 0..<nameLen:
      msg.folderName[i] = char(data[pos + i])
    pos += nameLen
    
    checkLen(4)
    let fileCount = readUint32(data, pos).int
    pos += 4
    
    msg.files = @[]
    for i in 0..<fileCount:
      checkLen(1)
      let pathLen = int(data[pos])
      pos += 1
      
      checkLen(pathLen)
      var path = newString(pathLen)
      for j in 0..<pathLen:
        path[j] = char(data[pos + j])
      pos += pathLen
      
      checkLen(16)
      let size = readInt64(data, pos)
      pos += 8
      let mtime = readInt64(data, pos)
      pos += 8
      
      checkLen(1)
      let hashLen = int(data[pos])
      pos += 1
      
      checkLen(hashLen)
      var hash = newString(hashLen)
      for j in 0..<hashLen:
        hash[j] = char(data[pos + j])
      pos += hashLen
      
      msg.files.add(FileEntry(path: path, size: size, mtime: mtime, hash: hash))
  
  of msgFileRequest:
    checkLen(1)
    let pathLen = int(data[pos])
    pos += 1
    
    checkLen(pathLen)
    msg.requestPath = newString(pathLen)
    for i in 0..<pathLen:
      msg.requestPath[i] = char(data[pos + i])
    pos += pathLen
    
    checkLen(12)
    msg.requestOffset = readInt64(data, pos)
    pos += 8
    msg.requestLength = cast[int32](readUint32(data, pos)).int
  
  of msgFileData:
    checkLen(22)
    msg.dataOffset = readInt64(data, pos)
    pos += 8
    msg.totalSize = readInt64(data, pos)
    pos += 8
    msg.done = data[pos] != 0
    pos += 1
    if data[pos] > ord(ckLz4):
      return err("Invalid compression kind")
    msg.dataCompression = CompressionKind(data[pos])
    pos += 1
    msg.dataOriginalLen = int(readUint32(data, pos))
    pos += 4
    
    checkLen(4)
    let dataLen = readUint32(data, pos).int
    pos += 4
    
    checkLen(dataLen)
    msg.data = data[pos..<pos+dataLen]
  
  of msgFileAck:
    checkLen(9)
    msg.success = data[pos] != 0
    pos += 1
    msg.bytesReceived = readInt64(data, pos)
  
  of msgFileDelete:
    checkLen(1)
    let pathLen = int(data[pos])
    pos += 1
    
    checkLen(pathLen)
    msg.deletedPath = newString(pathLen)
    for i in 0..<pathLen:
      msg.deletedPath[i] = char(data[pos + i])
  
  of msgPing:
    checkLen(8)
    msg.timestamp = readInt64(data, pos)
  
  of msgPong:
    checkLen(8)
    msg.pingTimestamp = readInt64(data, pos)

  of msgSyncDone:
    discard
  
  ok(msg)

proc newFileList*(folderName: string, files: seq[FileEntry]): ProtocolMessage =
  ProtocolMessage(kind: msgFileList, folderName: folderName, files: files)

proc newFileRequest*(path: string, offset: int64 = 0, length: int = -1): ProtocolMessage =
  ProtocolMessage(kind: msgFileRequest, requestPath: path, requestOffset: offset, requestLength: length)

proc newFileData*(
    data: seq[byte],
    offset: int64,
    totalSize: int64,
    done: bool = false,
    compression: CompressionKind = ckNone,
    originalLen: int = 0,
): ProtocolMessage =
  ProtocolMessage(
    kind: msgFileData,
    data: data,
    dataOffset: offset,
    totalSize: totalSize,
    done: done,
    dataCompression: compression,
    dataOriginalLen: if originalLen > 0: originalLen else: data.len
  )

proc newFileAck*(success: bool, bytesReceived: int64 = 0): ProtocolMessage =
  ProtocolMessage(kind: msgFileAck, success: success, bytesReceived: bytesReceived)

proc newFileDelete*(path: string): ProtocolMessage =
  ProtocolMessage(kind: msgFileDelete, deletedPath: path)

proc newPing*(): ProtocolMessage =
  ProtocolMessage(kind: msgPing, timestamp: getTime().toUnix())

proc newPong*(pingTimestamp: int64): ProtocolMessage =
  ProtocolMessage(kind: msgPong, pingTimestamp: pingTimestamp)

proc newSyncDone*(): ProtocolMessage =
  ProtocolMessage(kind: msgSyncDone)
