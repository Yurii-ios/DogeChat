/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

/*
 краткий список обязанностей:
1.Открытие соединения с сервером чата.
2.Разрешение пользователю присоединиться к чату, указав имя пользователя.
3.Разрешение пользователю отправлять и получать сообщения.
4.Закрытие соединения, когда вы закончите.
 */
import UIKit

protocol ChatRoomDelegate: class {
  func received(message: Message)
}

class ChatRoom: NSObject {
  //1 объявляем потоки ввода и вывода
  var inputStream: InputStream!
  var outputStream: OutputStream!

  weak var delegate: ChatRoomDelegate?
  
  //2 определяем username, где будете хранить имя текущего пользователя
  var username = ""

  //3  заявляем  maxReadLength. Эта константа ограничивает объем данных, которые можем отправить в одном сообщении.
  let maxReadLength = 4096
  
  func setupNetworkCommunication() {
    // 1 настраиваем два неинициализированных потока сокетов без автоматического управления памятью.
    var readStream: Unmanaged<CFReadStream>?
    var writeStream: Unmanaged<CFWriteStream>?

    // 2 связываем свои потоки сокетов чтения и записи вместе и подключаем их к сокету хоста, который в данном случае находится на порту 80.
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                       "localhost" as CFString,
                                       80,
                                       &readStream,
                                       &writeStream)
    inputStream = readStream?.takeRetainedValue()
    outputStream = writeStream?.takeRetainedValue()
    
    inputStream.delegate = self
    
    //нужно добавить эти потоки в цикл выполнения, чтобы  приложение правильно реагировало на сетевые события
    inputStream.schedule(in: .current, forMode: .common)
    outputStream.schedule(in: .current, forMode: .common)
    
    inputStream.open()
    outputStream.open()
  }
  
  func joinChat(username: String) {
    //1
    let data = "iam:\(username)".data(using: .utf8)!
    
    //2 сохраняем имя, чтобы потом использовать его для отправки сообщений чата
    self.username = username

    //3 withUnsafeBytes(_:) обеспечивает удобный способ работы с небезопасной версией указателя некоторых данных в безопасных пределах замыкания.
    _ = data.withUnsafeBytes {
      guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        print("Error joining chat")
        return
      }
      //4  пишем свое сообщение в выходной поток
      outputStream.write(pointer, maxLength: data.count)
    }
  }
}

extension ChatRoom: StreamDelegate {
  
  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
      switch eventCode {
      case .hasBytesAvailable:
        print("new message received")
        readAvailableBytes(stream: aStream as! InputStream)
      case .endEncountered:
        print("new message received")
        stopChatSession ()
      case .errorOccurred:
        print("error occurred")
      case .hasSpaceAvailable:
        print("has space available")
      default:
        print("some other event...")
      }
  }
  
  private func readAvailableBytes(stream: InputStream) {
    //1 Сначала устанавливаем буфер, в который можете читать входящие байты.
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReadLength)

    //2 выполняем цикл до тех пор, пока у входного потока есть байты для чтения.
    while stream.hasBytesAvailable {
      //3 В каждой точке вызываем read(_:maxLength:), который считывает байты из потока и помещает их в буфер, который  передаем
      let numberOfBytesRead = inputStream.read(buffer, maxLength: maxReadLength)

      //4
      if numberOfBytesRead < 0, let error = stream.streamError {
        print(error)
        break
      }

      // Construct the Message object
      if let message = processedMessageString(buffer: buffer, length: numberOfBytesRead) {
        // Notify interested parties
        delegate?.received(message: message)
      }

    }
  }
  
  private func processedMessageString(buffer: UnsafeMutablePointer<UInt8>,
                                      length: Int) -> Message? {
    //1 инициализируем  String используя переданный буфер и длину. обрабатываем текст как UTF-8, указываем, что String нужно освободить буфер от байтов, когда это будет сделано с ними, а затем разделяем входящее сообщение на символ :, чтобы  обрабатывать имя отправителя и сообщение в виде отдельных строк.
    guard
      let stringArray = String(
        bytesNoCopy: buffer,
        length: length,
        encoding: .utf8,
        freeWhenDone: true)?.components(separatedBy: ":"),
      let name = stringArray.first,
      let message = stringArray.last
      else {
        return nil
    }
    //2 Затем  выясняем, отправили ли сообщение или кто-то другой, основываясь на имени. В производственном приложении - использовать какой-то уникальный токен, но пока этого достаточно.
    let messageSender: MessageSender =
      (name == self.username) ? .ourself : .someoneElse
    //3  создаем объект Message из собранных частей и возвращаем его.
    return Message(message: message, messageSender: messageSender, username: name)
  }

  func send(message: String) {
    let data = "msg:\(message)".data(using: .utf8)!

    _ = data.withUnsafeBytes {
      guard let pointer = $0.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        print("Error joining chat")
        return
      }
      outputStream.write(pointer, maxLength: data.count)
    }
  }
  
  func  stopChatSession () {
    inputStream.close ()
    outputStream.close ()
  }
  
}
