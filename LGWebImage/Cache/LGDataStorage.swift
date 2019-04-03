//
//  LGDataStorage.swift
//  LGWebImage
//
//  Created by 龚杰洪 on 2017/9/7.
//  Copyright © 2017年 龚杰洪. All rights reserved.
//

import Foundation
import SQLite3


/// 持久存储对象
public struct LGDataStorageItem {
    public var key: String
    public var data: Data
    public var fileName: String?
    public var size: Int
    public var modifyTime: Int
    public var accessTime: Int
    public var extendedData: Data?
}

fileprivate enum LGDataStorageError: Error {
    case execSqlFailed(String)
    case invalidPath(String)
}

extension LGDataStorageError: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case let .execSqlFailed(sql):
            return "执行SQL语句失败: \(sql)"
        case let .invalidPath(reson):
            return "无效的文件路径: \(reson)"
        }
    }
}

/// 将文件写入磁盘存储
public class LGDataStorage {
    /// 存储类型
    ///
    /// - file: 文件
    /// - SQLite: SQLite
    /// - mixed: 文件&SQLite混合
    public enum StorageType {
        case file
        case SQLite
        case mixed
    }
    
    /// 静态配置，包含文件夹和文件名相关内容
    fileprivate struct Config {
        static var maxErrorRetryCount: Int {
            return 5
        }
        
        static var minRetryTimeInterval: TimeInterval {
            return 2.0
        }
        
        static var pathLengthMax: Int32 {
            return PATH_MAX - 64
        }
        
        static var dbFileName: String {
            return "manifest.sqlite"
        }
        
        static var dbShmFileName: String {
            return "manifest.sqlite-shm"
        }
        
        static var dbWalFileName: String {
            return "manifest.sqlite-wal"
        }
        
        static var dataDirectoryName: String {
            return "data"
        }
        
        static var trashDirectoryName: String {
            return "trash"
        }
    }
    
    
    fileprivate var _trashQueue: DispatchQueue
    fileprivate var _path: String
    fileprivate var _dbPath: String
    fileprivate var _dataPath: String
    fileprivate var _trashPath: String
    fileprivate var _db: OpaquePointer? = nil
    fileprivate var _dbStmtCache: [String: OpaquePointer]?
    fileprivate var _dbLastOpenErrorTime: TimeInterval = 0
    fileprivate var _dbOpenErrorCount: Int = 0
    fileprivate var _needCreateDir: Bool = true
    fileprivate let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    
    
    public private(set) var path: String
    public private(set) var type: LGDataStorage.StorageType
    
    public init(path: String, type: LGDataStorage.StorageType) throws {
        guard path.count > 0 && path.count < Config.pathLengthMax else {
            throw LGDataStorageError.invalidPath(path)
        }
        
        self.path = path
        self.type = type
        
        _path = path
        _trashPath = path + "/" + Config.trashDirectoryName
        _dataPath = path + "/" + Config.dataDirectoryName
        _dbPath = path + "/" + Config.dbFileName
        _trashQueue = DispatchQueue(label: "com.LGDataStorage.cache.disk.trash")
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: _trashPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                throw LGDataStorageError.invalidPath(_trashPath)
            }
        } else {
            try fileManager.createDirectory(atPath: path,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            try fileManager.createDirectory(atPath: _dataPath,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
            try fileManager.createDirectory(atPath: _trashPath,
                                            withIntermediateDirectories: true,
                                            attributes: nil)
        }
        
        if !_dbOpen() || !_dbInitlalize() {
            _ = _dbClose()
            _reset()
            if !_dbOpen() || !_dbInitlalize() {
                println("初始化失败", #file, #function, #line, #column)
                _ = _dbClose()
                return
            }
        }
        _fileEmptyTrashInBackground()
    }
    
    public func filePathURL(withFileName filename: String) -> URL {
        let path = _dataPath + "/" + filename
        return URL(fileURLWithPath: path)
    }
    
    public func saveItem(item: LGDataStorageItem) -> Bool {
        return _dbSaveWith(key: item.key,
                           value: item.data,
                           fileName: item.fileName,
                           extendedData: item.extendedData)
    }
    
    public func saveItem(with key: String, value: Data, filename: String? = nil, extendedData: Data? = nil) -> Bool {
        if key.lg_length == 0 || value.count == 0 {
            return false
        }
        
        if type == LGDataStorage.StorageType.file && (filename == nil || filename?.lg_length == 0) {
            return false
        }
        
        if filename != nil && filename!.lg_length > 0 {
            if !_fileWrite(with: filename!, data: value) {
                return false
            }
            
            if !_dbSaveWith(key: key, value: value, fileName: filename, extendedData: extendedData) {
                _ = _fileDelete(with: filename!)
                return false
            }
            return true
        } else {
            if type != LGDataStorage.StorageType.SQLite {
                let tempFileName = _dbGetFileName(withKey: key)
                if tempFileName != nil {
                    _ = _fileDelete(with: tempFileName!)
                }
            }
            
            return _dbSaveWith(key: key, value: value, fileName: filename, extendedData: extendedData)
        }
    }
    
    public func saveItem(with key: String,
                         fileURL: URL,
                         filename: String? = nil,
                         extendedData: Data? = nil) -> Bool
    {
        if key.lg_length == 0 {
            return false
        }
        
        if type == LGDataStorage.StorageType.file && (filename == nil || filename?.lg_length == 0) {
            return false
        }
        
        if filename != nil && filename!.lg_length > 0 {
            if !_fileMove(with: filename!, originURL: fileURL) {
                return false
            }
            
            if !_dbSaveWith(key: key, value: Data(), fileName: filename, extendedData: extendedData) {
                _ = _fileDelete(with: filename!)
                return false
            }
            return true
        } else {
            if type != LGDataStorage.StorageType.SQLite {
                let tempFileName = _dbGetFileName(withKey: key)
                if tempFileName != nil {
                    _ = _fileDelete(with: tempFileName!)
                }
            }
            
            return _dbSaveWith(key: key, value: Data(), fileName: filename, extendedData: extendedData)
        }
    }
    
    public func removeItem(forKey key: String) -> Bool {
        if key.lg_length == 0 {
            return false
        }
        
        var reslut: Bool = false
        
        switch type {
        case .file, .mixed:
            if let filename = _dbGetFileName(withKey: key) {
                _ = _fileDelete(with: filename)
            }
            reslut = _dbDeleteItemWith(key: key)
            break
        case .SQLite:
            reslut = _dbDeleteItemWith(key: key)
            break
        }
        
        return reslut
    }
    
    public func removeItem(forKeys keys: [String]) -> Bool {
        if keys.count == 0 {
            return false
        }
        
        var reslut: Bool = false
        
        switch type {
        case .file, .mixed:
            let filenames = _dbGetFileName(withKeys: keys)
            for filename in filenames {
                _ = _fileDelete(with: filename)
            }
            reslut = _dbDeleteItemWith(keys: keys)
            break
        case .SQLite:
            reslut = _dbDeleteItemWith(keys: keys)
            break
        }
        
        return reslut
    }
    
    public func removeItems(lagerThanSize size: Int) -> Bool {
        if size == Int.max {
            return true
        }
        
        if size <= 0 {
            removeAllItems()
        }
        
        switch type {
        case .SQLite:
            if _dbDeleteItemsWith(sizeLargerThan: size) {
                _dbCheckpoint()
                return true
            }
            break
        default:
            let filenames = _dbGetFilenames(withSizeLargerThan: size)
            for filename in filenames {
                _ = _fileDelete(with: filename)
            }
            if _dbDeleteItemsWith(sizeLargerThan: size) {
                _dbCheckpoint()
                return true
            }
            break
        }
        return false
    }
    
    public func removeItems(earlierThanTime time: Int) -> Bool {
        if time <= 0 {
            return false
        }
        
        if time == Int.max {
            return removeAllItems()
        }
        switch type {
        case .SQLite:
            if _dbDeleteItemsWith(timeEarlierThan: time) {
                _dbCheckpoint()
                return true
            }
            break
        default:
            let filenames = _dbGetFilenames(withTimeEarlierThan: time)
            for filename in filenames {
                _ = _fileDelete(with: filename)
            }
            if _dbDeleteItemsWith(timeEarlierThan: time) {
                _dbCheckpoint()
                return true
            }
            break
        }
        return false
    }
    
    public func removeItems(toFitSize maxSize: Int) -> Bool {
        if maxSize == Int.max {
            return true
        }
        
        if maxSize <= 0 {
            return removeAllItems()
        }
        
        var total = _dbGetTotalItemSize()
        var items = [LGDataStorageItem]()
        var success: Bool = false
        if total < 0 {
            return false
        }
        if total <= maxSize {
            return true
        }
        
        repeat {
            let perCount = 16
            items = _dbGetItemSizeInfo(orderByTimeAscWithLimit: perCount)
            for item in items {
                if total > maxSize {
                    if item.fileName != nil {
                        _ = _fileDelete(with: item.fileName!)
                    }
                    success = _dbDeleteItemWith(key: item.key)
                    total -= item.size
                } else {
                    break
                }
                if !success {
                    break
                }
            }
        } while total > maxSize && items.count > 0 && success
        if success {
            _dbCheckpoint()
        }
        return success
    }
    
    public func removeItems(toFitCount maxCount: Int) -> Bool {
        if maxCount == Int.max {
            return true
        }
        if maxCount <= 0 {
            return removeAllItems()
        }
        
        var total = _dbGetTotalItemCount()
        if total < 0 {
            return false
        }
        if total <= maxCount {
            return true
        }
        
        var items = [LGDataStorageItem]()
        var success: Bool = false
        
        repeat {
            let perCount = 16
            items = _dbGetItemSizeInfo(orderByTimeAscWithLimit: perCount)
            for item in items {
                if total > maxCount {
                    if item.fileName != nil {
                        _ = _fileDelete(with: item.fileName!)
                    }
                    success = _dbDeleteItemWith(key: item.key)
                    total -= item.size
                } else {
                    break
                }
                if !success {
                    break
                }
            }
        } while total > maxCount && items.count > 0 && success
        if success {
            _dbCheckpoint()
        }
        return success
    }
    
    @discardableResult
    public func removeAllItems() -> Bool {
        if !_dbClose() {
            return false
        }
        _reset()
        if !_dbOpen() {
            return false
        }
        if !_dbInitlalize() {
            return false
        }
        return true
    }
    
    public func removeAllItems(with progressBlock: ((_ removedCount: Int, _ totlaCount: Int) -> Void)?,
                               endBlock: ((_ error: Bool) -> Void)?) {
        let total = _dbGetTotalItemCount()
        if total <= 0 {
            if endBlock != nil {
                endBlock!(total < 0)
            }
        } else {
            var left = total
            let perCount = 32
            var items = [LGDataStorageItem]()
            var success: Bool = false
            
            repeat {
                items = _dbGetItemSizeInfo(orderByTimeAscWithLimit: perCount)
                for item in items {
                    if left > 0 {
                        if item.fileName != nil {
                            _ = _fileDelete(with: item.fileName!)
                        }
                        success = _dbDeleteItemWith(key: item.key)
                        left -= 1
                    } else {
                        break
                    }
                    if !success {
                        break
                    }
                    
                    if progressBlock != nil {
                        progressBlock!(total - left, total)
                    }
                }
            } while left > 0 && items.count > 0 && success
            
            if success {
                _dbCheckpoint()
            }
            if endBlock != nil {
                endBlock!(!success)
            }
        }
    }
    
    public func getItem(forKey key: String) -> LGDataStorageItem? {
        if key.lg_length == 0 {
            return nil
        }
        var item = _dbGetItem(withKey: key, excludeInlineData: false)
        if item != nil {
            _ = _dbUpdateAccessTimeWith(key: key)
        }
        
        if item?.fileName != nil {
            if let value = _fileRead(with: item!.fileName!) {
                item!.data = value
            } else {
                _ = _dbDeleteItemWith(key: key)
                item = nil
            }
        }
        return item
    }
    
    public func getItemInfo(forKey key: String) -> LGDataStorageItem? {
        if key.lg_length == 0 {
            return nil
        }
        
        return _dbGetItem(withKey: key, excludeInlineData: true)
    }
    
    public func getItemValue(forKey key: String) -> Data? {
        if key.lg_length == 0 {
            return nil
        }
        
        var value: Data? = nil
        
        switch type {
        case .SQLite:
            value = _dbGetValue(withKey: key)
            break
        case .file:
            let filename = _dbGetFileName(withKey: key)
            if filename != nil {
                if let tempValue = _fileRead(with: filename!) {
                    value = tempValue
                } else {
                    _ = _dbDeleteItemWith(key: key)
                    value = nil
                }
            } else {
                value = nil
            }
            break
        case .mixed:
            if let filename = _dbGetFileName(withKey: key) {
                if let tempValue = _fileRead(with: filename) {
                    value = tempValue
                } else {
                    _ = _dbDeleteItemWith(key: key)
                    value = nil
                }
            } else {
                value = _dbGetValue(withKey: key)
            }
            break
        }
        if value != nil {
            _ = _dbUpdateAccessTimeWith(key: key)
        }
        return value
    }
    
    public func getItems(forKeys keys: [String]) -> [LGDataStorageItem] {
        if keys.count == 0 {
            return [LGDataStorageItem]()
        }
        
        var items = _dbGetItem(withKeys: keys, excludeInlineData: false)
        if type == LGDataStorage.StorageType.SQLite {
            for index in 0..<items.count {
                var item = items[index]
                if item.fileName != nil {
                    if let tempValue = _fileRead(with: item.fileName!){
                        item.data = tempValue
                    }
                    else {
                        _ = _dbDeleteItemWith(key: item.key)
                        items.remove(at: index)
                    }
                }
            }
        }
        
        if items.count > 0 {
            _ = _dbUpdateAccessTimeWith(keys: keys)
        }
        return items
    }
    
    public func getItemInfo(forKeys keys: [String]) -> [LGDataStorageItem] {
        if keys.count == 0 {
            return [LGDataStorageItem]()
        }
        return _dbGetItem(withKeys: keys, excludeInlineData: true)
    }
    
    public func getItemsValue(forKeys keys: [String]) -> [String: Data] {
        let items = getItems(forKeys: keys)
        var result = [String: Data]()
        
        for item in items {
            result[item.key] = item.data
        }
        
        return result
    }
    
    public func itemExists(forKey key: String) -> Bool {
        if key.lg_length == 0 {
            return false
        }
        return _dbGetItemCount(withKey: key) > 0
    }
    
    public func getItemsCount() -> Int {
        return _dbGetTotalItemCount()
    }
    
    public func getItemsSize() -> Int {
        return _dbGetTotalItemSize()
    }
    
    deinit {
        let taskId = UIApplication.shared.beginBackgroundTask {
            
        }
        _dbClose()
        
        if taskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }
    
    
}




// MARK: - 数据库私有操作
extension LGDataStorage {
    fileprivate func _dbOpen() -> Bool {
        if _db != nil {
            return true
        }
        
        let result = sqlite3_open(_dbPath, &_db)
        if result == SQLITE_OK {
            _dbStmtCache = [String: OpaquePointer]()
            _dbLastOpenErrorTime = 0
            _dbOpenErrorCount = 0
            return true
        } else {
            _db = nil
            if _dbStmtCache != nil {
                _dbStmtCache = nil
                _dbLastOpenErrorTime = CACurrentMediaTime()
                _dbOpenErrorCount += 1
            }
            
            /*#file - String - The name of the file in which it appears.
             
             #line - Int - The line number on which it appears.
             
             #column - Int - The column number in which it begins.
             
             #function - String - The name of the declaration in which it appears.
             */
            println("初始化sqlite失败", #file, #function, #line, #column)
            return false
        }
    }
    
    @discardableResult
    fileprivate func _dbClose() -> Bool {
        if _db == nil {
            return true
        }
        
        var result: Int32 = 0
        var retry: Bool = false
        var stmtFinalized: Bool = false
        if _dbStmtCache != nil {
            _dbStmtCache = nil
        }
        
        repeat {
            retry = false
            result = sqlite3_close(_db!)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                if !stmtFinalized {
                    stmtFinalized = true
                    var stmt: OpaquePointer? = sqlite3_next_stmt(_db!, nil)
                    
                    while stmt != nil {
                        stmt = sqlite3_next_stmt(_db!, stmt)
                        retry = true
                    }
                    sqlite3_finalize(stmt) // ??
                }
                
            } else if result != SQLITE_OK {
                println("关闭数据库连接失败", #file, #function, #line, #column)
            }
        } while retry
        
        _db = nil
        return true
    }
    
    fileprivate func _dbInitlalize() -> Bool {
        let sql = "pragma journal_mode = wal; pragma synchronous = normal; create table if not exists manifest" +
            " (key text, filename text, size integer, inline_data blob, modification_time integer," +
            " last_access_time integer, extended_data blob, primary key(key)); " +
            "create index if not exists last_access_time_idx on manifest(last_access_time);" +
        "create index if not exists key_idx on manifest(key);"
        
        return _dbExecute(sql: sql)
    }
    
    fileprivate func _dbCheck() -> Bool {
        if _db == nil {
            if _dbOpenErrorCount < Config.maxErrorRetryCount &&
                CACurrentMediaTime() - _dbLastOpenErrorTime > Config.minRetryTimeInterval {
                return self._dbOpen() && self._dbInitlalize()
            } else {
                return false
            }
        } else {
            return true
        }
    }
    
    fileprivate func _dbExecute(sql: String) -> Bool {
        if sql.count == 0 {
            return false
        }
        
        if !self._dbCheck() {
            return false
        }
        
        do {
            var error: UnsafeMutablePointer<Int8>? = nil
            let result = sqlite3_exec(_db!, sql, nil, nil, &error)
            guard result == SQLITE_OK, error == nil else {
                throw LGDataStorageError.execSqlFailed(sql)
            }
            return true
        } catch {
            println(error, #file, #function, #line, #column, sql)
            return false
        }
    }
    
    fileprivate func _dbCheckpoint() {
        if !_dbCheck() {
            return
        }
        sqlite3_wal_checkpoint(_db!, nil)
    }
    
    fileprivate func _dbPrepareStmt(sql: String) -> OpaquePointer? {
        if !_dbCheck() || sql.count == 0 || _dbStmtCache == nil {
            return nil
        }
        
        var stmt = _dbStmtCache![sql]
        if stmt == nil {
            let result = sqlite3_prepare_v2(_db!, sql, -1, &stmt, nil)
            guard result == SQLITE_OK else {
                return nil
            }
            _dbStmtCache![sql] = stmt
        } else {
            sqlite3_reset(stmt)
        }
        return stmt
    }
    
    fileprivate func _dbJoinedKeys(keys: [String]) -> String {
        var resultStr = ""
        let count = keys.count
        for index in 0..<count {
            resultStr += "?"
            if (index + 1) != count {
                resultStr += ","
            }
        }
        return resultStr
    }
    
    fileprivate func _dbBind(joinedKeys: [String], stmt: OpaquePointer, index: Int) {
        let count = joinedKeys.count
        for i in 0..<count {
            let key = joinedKeys[i]
            sqlite3_bind_text(stmt, Int32(index + i), key, -1, SQLITE_TRANSIENT)
        }
    }
    
    fileprivate func _dbSaveWith(key: String,
                                 value: Data,
                                 fileName: String? = nil,
                                 extendedData: Data? = nil) -> Bool
    {
        let sql =   "insert or replace into manifest (key, filename, size, inline_data," +
        " modification_time, last_access_time, extended_data) values (?1, ?2, ?3, ?4, ?5, ?6, ?7);"
        
        let stmt = _dbPrepareStmt(sql: sql)
        if stmt == nil {
            return false
        }
        
        let timestmap = Int32(time(nil))
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, fileName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 3, Int32(value.count))
        if fileName == nil || fileName?.count == 0 {
            let pointer = value.withUnsafeBytes { (bytes) in
                return bytes.baseAddress
            }
            sqlite3_bind_blob(stmt, 4, pointer, Int32(value.count), SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_blob(stmt, 4, nil, 0, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(stmt, 5, timestmap)
        sqlite3_bind_int(stmt, 6, timestmap)
        
        if let extendedData = extendedData {
            let pointer = extendedData.withUnsafeBytes { bytes in
                return bytes.baseAddress
            }
            sqlite3_bind_blob(stmt, 7, pointer, Int32(extendedData.count), SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_blob(stmt, 7, nil, 0, SQLITE_TRANSIENT)
        }
        
        let result = sqlite3_step(stmt)
        
        guard result == SQLITE_DONE else {
            println("插入数据失败", #file, #function, #line, #column, result)
            return false
        }
        
        return true
    }
    
    fileprivate func _dbUpdateAccessTimeWith(key: String) -> Bool {
        let sql = "update manifest set last_access_time = ?1 where key = ?2;"
        let stmt = _dbPrepareStmt(sql: sql)
        if stmt == nil {
            return false
        }
        sqlite3_bind_int(stmt, 1, Int32(time(nil)))
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            println("更新数据失败", #file, #function, #line, #column, result)
            return false
        }
        return true
    }
    
    fileprivate func _dbUpdateAccessTimeWith(keys: [String]) -> Bool {
        if !_dbCheck() {
            return false
        }
        let timestmap = Int32(time(nil))
        let sql = String(format: "update manifest set last_access_time = %d where key in (%@);",
                         timestmap,
                         _dbJoinedKeys(keys: keys))
        
        var stmt: OpaquePointer? = nil
        
        var result = sqlite3_prepare_v2(_db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            println("准备数据失败,%d", #file, #function, #line, #column, result)
            return false
        }
        
        _dbBind(joinedKeys: keys, stmt: stmt!, index: 1)
        result = sqlite3_step(stmt)
        
        guard result == SQLITE_DONE else {
            println("更新数据失败", #file, #function, #line, #column, result)
            return false
        }
        return true
    }
    
    fileprivate func _dbDeleteItemWith(key: String) -> Bool {
        let sql = "delete from manifest where key = ?1;"
        let stmt = _dbPrepareStmt(sql: sql)
        if stmt == nil {
            return false
        }
        
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            println("删除数据失败", #file, #function, #line, #column, result)
            return false
        }
        
        return true
    }
    
    fileprivate func _dbDeleteItemWith(keys: [String]) -> Bool {
        if !_dbCheck() {
            return false
        }
        
        let sql = String(format: "delete from manifest where key in (%@);", _dbJoinedKeys(keys: keys))
        
        var stmt: OpaquePointer? = nil
        
        var result = sqlite3_prepare_v2(_db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            return false
        }
        
        _dbBind(joinedKeys: keys, stmt: stmt!, index: 1)
        
        result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        
        guard result == SQLITE_DONE else {
            println("删除数据失败", #file, #function, #line, #column, result)
            return false
        }
        
        return true
    }
    
    
    /// 删除超过size大小的记录
    ///
    /// - Parameter size: 大小阈值
    /// - Returns: 是否删除成功
    fileprivate func _dbDeleteItemsWith(sizeLargerThan size: Int) -> Bool {
        let sql = "delete from manifest where size > ?1;"
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return false
        }
        
        sqlite3_bind_int(stmt, 1, Int32(size))
        let result = sqlite3_step(stmt)
        guard result == SQLITE_OK else {
            return false
        }
        
        return true
    }
    
    fileprivate func _dbDeleteItemsWith(timeEarlierThan time: Int) -> Bool {
        let sql = "delete from manifest where last_access_time < ?1;"
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return false
        }
        
        sqlite3_bind_int(stmt, 1, Int32(time))
        let result = sqlite3_step(stmt)
        guard result == SQLITE_OK else {
            return false
        }
        
        return true
    }
    
    fileprivate func _dbGetItem(from stmt: OpaquePointer, excludeInlineData: Bool) -> LGDataStorageItem {
        var index: Int32 = 0
        
        let key = sqlite3_column_text(stmt, index)
        
        index += 1
        let fileName = sqlite3_column_text(stmt, index)
        
        index += 1
        let size = sqlite3_column_int(stmt, index)
        
        index += 1
        let inline_data = excludeInlineData ? nil : sqlite3_column_blob(stmt, index)
        
        let inline_data_bytes = excludeInlineData ? 0 : sqlite3_column_bytes(stmt, index)
        
        index += 1
        let modification_time = sqlite3_column_int(stmt, index)
        
        index += 1
        let last_access_time = sqlite3_column_int(stmt, index)
        
        index += 1
        let extended_data = excludeInlineData ? nil : sqlite3_column_blob(stmt, index)
        
        let extended_data_bytes = sqlite3_column_bytes(stmt, index)
        
        
        let keyString = (key != nil) ? String(cString: key!) : ""
        let fileNameString = (fileName != nil) ? String(cString: fileName!) : nil
        var valueData = Data()
        if inline_data != nil && inline_data_bytes > 0 {
            valueData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: inline_data!),
                             count: Int(inline_data_bytes),
                             deallocator: .none)
        }
        
        var extendedData: Data? = nil
        if extended_data != nil && extended_data_bytes > 0 {
            extendedData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: extended_data!),
                                count: Int(extended_data_bytes),
                                deallocator: .none)
        }
        
        let item = LGDataStorageItem(key: keyString,
                                     data: valueData,
                                     fileName: fileNameString,
                                     size: Int(size),
                                     modifyTime: Int(modification_time),
                                     accessTime: Int(last_access_time),
                                     extendedData: extendedData)
        
        return item
    }
    
    fileprivate func _dbGetItem(withKey key: String, excludeInlineData: Bool) -> LGDataStorageItem? {
        var sql: String
        if excludeInlineData {
            sql =   "select key, filename, size, modification_time, last_access_time," +
            " extended_data from manifest where key = ?1;"
        } else {
            sql =   "select key, filename, size, inline_data, modification_time, last_access_time," +
            " extended_data from manifest where key = ?1;"
        }
        
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return nil
        }
        
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        var resultItem: LGDataStorageItem? = nil
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            resultItem = _dbGetItem(from: stmt!, excludeInlineData: excludeInlineData)
        } else {
            if result == SQLITE_DONE {
                // 数据库无记录，直接step finished
            } else {
                println("查询数据失败", #file, #function, #line, #column, result)
            }
        }
        return resultItem
    }
    
    fileprivate func _dbGetItem(withKeys keys: [String], excludeInlineData: Bool) -> [LGDataStorageItem] {
        var resultArray = [LGDataStorageItem]()
        if !_dbCheck() {
            return resultArray
        }
        let sql: String
        if excludeInlineData {
            sql = String(format: "select key, filename, size, modification_time, last_access_time," +
                " extended_data from manifest where key in (%@);",
                         _dbJoinedKeys(keys: keys))
        } else {
            sql = String(format: "select key, filename, size, inline_data, modification_time, " +
                "last_access_time, extended_data from manifest where key in (%@);",
                         _dbJoinedKeys(keys: keys))
        }
        
        var stmt: OpaquePointer? = nil
        var result = sqlite3_prepare_v2(_db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            return resultArray
        }
        
        _dbBind(joinedKeys: keys, stmt: stmt!, index: 1)
        repeat {
            result = sqlite3_step(stmt)
            if result == SQLITE_ROW {
                let item = _dbGetItem(from: stmt!, excludeInlineData: excludeInlineData)
                resultArray.append(item)
            } else if result == SQLITE_DONE {
                break
            } else {
                break
            }
            
            
        } while true
        
        sqlite3_finalize(stmt)
        return resultArray
    }
    
    fileprivate func _dbGetValue(withKey key: String) -> Data? {
        let sql = "select inline_data from manifest where key = ?1;"
        let stmt: OpaquePointer? = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return nil
        }
        
        sqlite3_bind_text(stmt!, 1, key, -1, SQLITE_TRANSIENT)
        
        let result = sqlite3_step(stmt!)
        if result == SQLITE_ROW {
            let inline_data = sqlite3_column_blob(stmt, 0)
            let inline_data_bytes = sqlite3_column_bytes(stmt!, 0)
            
            if inline_data == nil || inline_data_bytes <= 0 {
                return nil
            } else {
                return Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: inline_data!),
                            count: Int(inline_data_bytes),
                            deallocator: .none)
            }
        } else {
            return nil
        }
        
    }
    
    fileprivate func _dbGetFileName(withKey key: String) -> String? {
        let sql = "select filename from manifest where key = ?1;"
        let stmt: OpaquePointer? = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return nil
        }
        
        sqlite3_bind_text(stmt!, 1, key, -1, SQLITE_TRANSIENT)
        
        let result = sqlite3_step(stmt!)
        if result == SQLITE_ROW {
            let filename = sqlite3_column_text(stmt, 0)
            
            if filename != nil {
                return String(cString: filename!)
            } else {
                return nil
            }
        } else {
            return nil
        }
        
    }
    
    fileprivate func _dbGetFileName(withKeys keys: [String]) -> [String] {
        if !_dbCheck() {
            return [String]()
        }
        let sql = String(format: "select filename from manifest where key in (%@);", _dbJoinedKeys(keys: keys))
        var stmt: OpaquePointer? = nil
        var result = sqlite3_prepare_v2(_db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            return [String]()
        }
        
        _dbBind(joinedKeys: keys, stmt: stmt!, index: 1)
        
        var resultArray = [String]()
        repeat {
            result = sqlite3_step(stmt!)
            if result == SQLITE_ROW {
                let filename = sqlite3_column_text(stmt!, 0)
                if filename != nil {
                    resultArray.append(String(cString: filename!))
                }
            } else {
                break
            }
        } while true
        sqlite3_finalize(stmt)
        return resultArray
    }
    
    fileprivate func _dbGetFilenames(withSizeLargerThan size: Int) -> [String] {
        let sql = "select filename from manifest where size > ?1 and filename is not null;"
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return [String]()
        }
        
        sqlite3_bind_int(stmt!, 1, Int32(size))
        var resultArray = [String]()
        repeat {
            let result = sqlite3_step(stmt!)
            if result == SQLITE_ROW {
                let filename = sqlite3_column_text(stmt, 0)
                if filename != nil {
                    let name = String(cString: filename!)
                    resultArray.append(name)
                } else {
                    break
                }
            } else {
                break
            }
        } while true
        
        return resultArray
    }
    
    fileprivate func _dbGetFilenames(withTimeEarlierThan time: Int) -> [String] {
        let sql = "select filename from manifest where last_access_time < ?1 and filename is not null;"
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return [String]()
        }
        
        sqlite3_bind_int(stmt!, 1, Int32(time))
        var resultArray = [String]()
        repeat {
            let result = sqlite3_step(stmt!)
            if result == SQLITE_ROW {
                let filename = sqlite3_column_text(stmt, 0)
                if filename != nil {
                    let name = String(cString: filename!)
                    resultArray.append(name)
                } else {
                    break
                }
            } else {
                break
            }
        } while true
        
        return resultArray
    }
    
    fileprivate func _dbGetItemSizeInfo(orderByTimeAscWithLimit count: Int) -> [LGDataStorageItem] {
        let sql = "select key, filename, size from manifest order by last_access_time asc limit ?1;"
        let stmt: OpaquePointer? = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return [LGDataStorageItem]()
        }
        
        sqlite3_bind_int(stmt!, 1, Int32(count))
        var resultArray = [LGDataStorageItem]()
        repeat {
            let result = sqlite3_step(stmt!)
            if result == SQLITE_ROW {
                let key = sqlite3_column_text(stmt!, 0)
                let filename = sqlite3_column_text(stmt!, 1)
                let size = sqlite3_column_int(stmt!, 2)
                
                if key != nil {
                    let keyStr = (key != nil ? String(cString: key!) : "")
                    let filenameStr = (filename != nil ? String(cString: filename!) : nil)
                    var item = LGDataStorageItem(key: "",
                                                 data: Data(),
                                                 fileName: nil,
                                                 size: 0,
                                                 modifyTime: 0,
                                                 accessTime: 0,
                                                 extendedData: nil)
                    item.key = keyStr
                    item.fileName = filenameStr
                    item.size = Int(size)
                    resultArray.append(item)
                } else {
                    break
                }
            } else {
                break
            }
        } while true
        return resultArray
    }
    
    fileprivate func _dbGetItemCount(withKey key: String) -> Int {
        let sql = "select count(key) from manifest where key = ?1;"
        let stmt = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return -1
        }
        
        let result = sqlite3_step(stmt!)
        
        guard result == SQLITE_ROW else {
            return -1
        }
        
        let count = sqlite3_column_int(stmt!, 0)
        return Int(count)
    }
    
    fileprivate func _dbGetTotalItemSize() -> Int {
        let sql = "select sum(size) from manifest;"
        let stmt: OpaquePointer? = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return -1
        }
        
        let result = sqlite3_step(stmt!)
        if result == SQLITE_ROW {
            let size = sqlite3_column_int(stmt, 0)
            return Int(size)
        }
        return -1
    }
    
    fileprivate func _dbGetTotalItemCount() -> Int {
        let sql = "select count(*) from manifest;"
        let stmt: OpaquePointer? = _dbPrepareStmt(sql: sql)
        guard stmt != nil else {
            return -1
        }
        
        let result = sqlite3_step(stmt!)
        if result == SQLITE_ROW {
            let size = sqlite3_column_int(stmt, 0)
            return Int(size)
        }
        return -1
    }
}

// MARK: -  文件私有操作
extension LGDataStorage {
    
    
    fileprivate func _fileWrite(with fileName: String, data: Data) -> Bool {
        let path = _dataPath + "/" + fileName
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            return false
        }
        return true
    }
    
    fileprivate func _fileRead(with fileName: String) -> Data? {
        let path = _dataPath + "/" + fileName
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return data
        } catch {
            return nil
        }
    }
    
    fileprivate func _fileDelete(with fileName: String) -> Bool {
        let path = _dataPath + "/" + fileName
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }
    
    fileprivate func _fileMove(with fileName: String, originURL: URL) -> Bool {
        let path = _dataPath + "/" + fileName
        let pathURL = URL(fileURLWithPath: path)
        
        // 就是原始路径，直接返回
        if pathURL == originURL {
            return true
        }
        
        if _needCreateDir {
            do {
                // 如果目标路径的文件夹未事先创建，则直接创建文件夹
                var isDirectory: ObjCBool = false
                let dirPath = pathURL.deletingLastPathComponent().absoluteString
                let dirIsExists = FileManager.default.fileExists(atPath: dirPath,
                                                                 isDirectory: &isDirectory)
                if !(isDirectory.boolValue && dirIsExists) {
                    try FileManager.default.createDirectory(at: pathURL.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                }
                _needCreateDir = false
                
                // 拷贝文件到目标路径
                try FileManager.default.moveItem(at: originURL, to: pathURL)
                return true
            } catch {
                return false
            }
        } else {
            do {
                // 拷贝文件到目标路径
                try FileManager.default.moveItem(at: originURL, to: pathURL)
                return true
            } catch {
                return false
            }
        }
    }
    
    fileprivate func _fileMoveAllToTrash() -> Bool {
        let uuid = UUID()
        let tempPath = _trashPath + "/" + uuid.uuidString
        
        do {
            try FileManager.default.moveItem(at: URL(fileURLWithPath: _dataPath),
                                             to: URL(fileURLWithPath: tempPath))
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: _dataPath),
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            return true
        } catch {
            return false
        }
    }
    
    fileprivate func _fileEmptyTrashInBackground() {
        let trashPath = _trashPath
        let trashQueue = _trashQueue
        trashQueue.async {
            let fileManager = FileManager.default
            do {
                let directoryContents = try fileManager.contentsOfDirectory(atPath: trashPath)
                for tempPath in directoryContents {
                    let fullPath = trashPath + "/" + tempPath
                    try fileManager.removeItem(atPath: fullPath)
                }
            } catch {
                
            }
        }
    }
    
    
    /// 删除所有文件，并在后台清理回收站
    /// 注意需要确保数据库连接已经关闭
    fileprivate func _reset() {
        do {
            let fileManager = FileManager.default
            try fileManager.removeItem(atPath: _path + "/" + Config.dbFileName)
            try fileManager.removeItem(atPath: _path + "/" + Config.dbShmFileName)
            try fileManager.removeItem(atPath: _path + "/" + Config.dbWalFileName)
            _ = _fileMoveAllToTrash()
            _fileEmptyTrashInBackground()
        } catch {
            
        }
    }
}


