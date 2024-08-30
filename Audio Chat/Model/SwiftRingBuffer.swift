//
//  SwiftRingBuffer.swift
//  Audio Chat
//
//  Created by Brown Diamond Tech on 8/30/24.
//

import Foundation

// MARK: - Ring Buffer Status
public enum RingBufferStatus {

    case empty
    case data
    case full

}


// MARK: - Ring Buffer Class
// Circular Buffer
public struct RingBuffer<T> {

    // MARK: - Properties
    let size: UInt
    var buffer: [T?]

    var head: UInt = 0
    var tail: UInt = 0
    
    let lock = NSLock()

    public var dataLength: UInt {
        return head &- tail
    }

    public var data: [T?] {
        var data = [T?]()
        for i in 0..<dataLength {
            //data.append(buffer[constrainInRange(tail + i)])
            data.append(buffer[Int(constrainInRange(tail + i))])
        }
        return data
    }

    // MARK: - Status
//    var status: RingBufferStatus
    var status: RingBufferStatus {
        if dataLength == 0 { return .empty }
        if dataLength == size { return .full}
        return .data
    }

    public var isEmpty: Bool {
        return self.status == .empty
    }

    public var isFull: Bool {
        return self.status == .full
    }

    public var hasData: Bool {
        return self.status != .empty
    }

    //
    // MARK: - Initializer
    //
    public init(size: Int) {
        
        self.size = UInt(size)
        self.buffer = [T?](repeating: nil, count: size)
        self.buffer.reserveCapacity(size)

    }

  
    
    
    //
    // MARK: - Helpers
    //
    func constrainInRange(_ value: UInt) -> UInt {
        return value & (self.size - 1)
    }

    //
    // MARK: - Write
    //
    @discardableResult
    public mutating func write(_ element: T) -> Bool {

        guard !isFull else { return false }

        lock.lock()
        //self.buffer[constrainInRange(head)] = element
        self.buffer[Int(constrainInRange(head))] = element
        head += 1
        lock.unlock()
        
        return true

    }

    @discardableResult
    public mutating func write(_ array: [T]) -> Bool {

        guard !isFull else { return false }

        if array.count > self.size { return false }

        for element in array {
            self.write(element)
        }

        return true

    }

    //
    // MARK: - Read
    //
    public mutating func read() -> T? {

        guard !isEmpty else { return nil }

        lock.lock()
        //let element = self.buffer[constrainInRange(tail)]
        let element = self.buffer[Int(constrainInRange(self.tail))]
        //self.buffer[constrainInRange(tail)] = nil
        self.buffer[Int(constrainInRange(tail))] = nil
        tail += 1
        lock.unlock()
        return element

    }

    @discardableResult
    public mutating func read(to buffer: inout T) -> RingBufferStatus {
        return .empty
    }

    public mutating func read(length: UInt) -> [T]? {
        return [T]()
    }

    @discardableResult
    public func read(to buffer: UnsafeMutableRawPointer!, length: UInt) -> RingBufferStatus {
        return .empty
    }

    //
    // MARK: - Peek
    //
    public func peek(at position: UInt) -> T? {
        return nil
    }

    @discardableResult
    public func peek(at position: UInt, to buffer: inout T) -> RingBufferStatus {
        return .empty
    }

    public func peek(at position: UInt, length: UInt) -> [T]? {
        return [T]()
    }

    public func peek(start: UInt, end: UInt) -> [T]? {
        return [T]()
    }

    @discardableResult
    public func peek(at position: UInt, to buffer: UnsafeMutableRawPointer!, length: UInt) -> RingBufferStatus {
        return .empty
    }

    @discardableResult
    public func peek(start: UInt, end: UInt, to buffer: UnsafeMutableRawPointer!, length: UInt) -> RingBufferStatus {
        return .empty
    }

    //
    // MARK: - Clear/Dump
    //
    @discardableResult
    public func dump() -> RingBufferStatus {
        return .empty
    }

    @discardableResult
    public func dump(toPosition position: UInt) -> RingBufferStatus {
        return .empty
    }

    public mutating func clear() {

        self.buffer = [T]()
        self.buffer.reserveCapacity(Int(size))
        //self.status = .empty
        self.tail = 0
        self.head = 0
    }

}

// FIXME: index out of range
/*extension Array {

    subscript(i: UInt) -> Element {

        get {
            return self[Int(i)]
        }

        set(from) {
            self[Int(i)] = from
        }

    }

}*/
