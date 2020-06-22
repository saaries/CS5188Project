//
//  DataController.swift
//  ObjectRecognizer
//
//  Created by 李心妍 on 2020/4/14.
//  Copyright © 2020 Mariusz Osowski. All rights reserved.
//

import Foundation

struct Fruit: Codable {
    var name: String
    var calories: String
    var tips: String
}

class DataController {
    func loadJson(_ fileName: String) -> [Fruit]? {
        if let url = Bundle.main.url(forResource: "FruitInfo", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let jsdecoder = JSONDecoder()
                let jsData = try jsdecoder.decode([Fruit].self, from: data)
                return jsData
            } catch {
                print("error when load json:\(error)")
            }
        }
        return nil
    }
}
