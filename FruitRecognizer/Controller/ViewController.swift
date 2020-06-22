//
//  ViewController.swift
//  ObjectRecognizer
//
//  Created by 李心妍 on 2020/3/28.
//  Copyright © 2020 Mariusz Osowski. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    //
    @IBOutlet weak var classificationLabel: UILabel!
    
    var currentfruit : Fruit?
    var fruitlist: [Fruit]?
    var planeNode: SCNNode?
    var cardDictionary = [String : SCNNode]()
    var card: SCNNode?
    var point: SCNNode?
    var ClassificationResult = ""
    var model: VNCoreMLModel?
//    var ConfidenceOject: Bool = false
    var ConfidenceValue: Float = 0.0
    
    
    private let dataController = DataController()
    // For parallel programming
    let dispatchQueue = DispatchQueue(label: "None.scsdzcsd")
    
    // For using CoreML
    lazy var coreMLRequest: VNCoreMLRequest = {
        do {
            // Call a CoreML model
            let model = try VNCoreMLModel(for: CoreMLFruit().model)
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, err in
                self?.ClassificationRequest(for: request, error: err)
            })
            // Define how we clip the input image
            request.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
            return request
        } catch {
            fatalError("Error in loading ML model: \(error)")
        }
    }()
    
    // Default function: usinv SceneKit
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.showsStatistics = false
        
        let scene = SCNScene(named: "art.scnassets/SceneKit Scene.scn")!
        sceneView.autoenablesDefaultLighting = true
        sceneView.scene = scene
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        sceneView.addGestureRecognizer(tapRecognizer)
        
        // Start calling ML model to do classification (Endless loop)
        CallFruitML()
    }
    
    // Deafult function
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
    }
    
        // Deafult function
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    // Tap Event, the tapped position will show a dot and the introduction card
    @objc func handleTap(sender: UITapGestureRecognizer) {
        // if there is a card, remove it before we add a new one (so card will not overlap)
            if self.card != nil{
                self.card!.removeFromParentNode()
        }

        // If ConfidenceOject is false, no object recognized, skip the following part
            if self.ConfidenceValue <= 0.5{
            self.classificationLabel.text = "No recognized fruit object ;) !"
        }
        
        // catch tapped position
        //if sender.state == .ended && self.ConfidenceOject == true{
            
        if sender.state == .ended && self.ConfidenceValue > 0.9{
            let TappedPosition = sender.location(in: sceneView)
            
            // HitTest will provide us info about distance, map point, ground surface
            let HitTest = sceneView.hitTest(TappedPosition, types: .featurePoint)
            
            guard let FirstHitTest = HitTest.first else { return }
            
            let ShowPosition = SCNVector3(FirstHitTest.worldTransform.columns.3.x,
                                          FirstHitTest.worldTransform.columns.3.y,
                                          FirstHitTest.worldTransform.columns.3.z)
            
            // Show the introduction card of recognize fruit
            ShowCard(position: ShowPosition, fruit: currentfruit)
            
            // Show the sound of recognize fruit
            ShowSound(fruit: currentfruit)
            
            // Show the tapped point
            self.ShowDot(position: ShowPosition,fruit: self.currentfruit)
        }
    }
    
    // Use online resource
    func ShowSound(fruit: Fruit?) {
        guard let name = fruit?.name else { return }
        
        // Use sound resource supported by Google Translate
        let str1 = "https://ssl.gstatic.com/dictionary/static/sounds/oxford/"
        let str2 = fruit?.name
        let str3 = "--_gb_1.mp3"
        
        let arry = str2!.components(separatedBy: " ")
        // print("split result:", arry.first)
        // So we won't get 404 url due to word length
        let urlstring = str1 + arry.first! + str3
        let LowerCaseURL = urlstring.lowercased
        
        var player: AVPlayer!
        let url = URL.init(string:LowerCaseURL())
        
        let SoundPlayer: AVPlayerItem = AVPlayerItem(url: url!)
        player = AVPlayer(playerItem: SoundPlayer)

        let playerLayer = AVPlayerLayer(player: player!)

        playerLayer.frame = CGRect(x: 0, y: 0, width: 10, height: 50)
        self.view.layer.addSublayer(playerLayer)
        player.play()
        
//      Do not use resource from project
//      var soundID:SystemSoundID = 0
//      let path = Bundle.main.path(forResource: "banana", ofType: "mp3")
//      let baseURL = NSURL(fileURLWithPath: path!)
//      AudioServicesCreateSystemSoundID(baseURL, &soundID)
//      AudioServicesPlayAlertSound(soundID)
    }
    
    func ClassificationRequest(for request: VNRequest, error: Error?) {
        guard let ClassificationResults = request.results else { return }
        
        let classifications = ClassificationResults as! [VNClassificationObservation]
        
        // Only show the highest one
        if let bestResult = classifications.first(where: {result in result.confidence > 0.9}) {
            ConfidenceValue = classifications.first!.confidence
            
            //print("Predict Result:",bestResult.identifier )
            self.fruitlist = dataController.loadJson("FruitInfo")!
            self.fruitlist?.forEach({ (currentfruit) in
                if currentfruit.name ==  bestResult.identifier {
                    self.currentfruit = currentfruit
                }
            })
            // Show confidence in classificationLabel
            DispatchQueue.main.sync {
                self.classificationLabel.text = "\(bestResult.identifier) : \(bestResult.confidence)"
            }
            
        }else{
//            DispatchQueue.main.sync {
//                self.classificationLabel.text = "No fruit object recognized!"
//            }
        }
    }
    
    // Run CoreML model in parallel
    func CallFruitML() {
        dispatchQueue.async {
            while true {
                self.updateCoreML()
            }
        }
    }
    
    // Run CoreML model
    func updateCoreML() {
        guard let pixelBuffer = sceneView.session.currentFrame?.capturedImage else { return }
        
        let ImgRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .left)
        
        do {
            // try to do classification
            try ImgRequestHandler.perform([coreMLRequest])
        } catch {
            print("Image request handler error: ", error.localizedDescription)
        }
    }

    // Show dot on tapped position
    func ShowDot(position: SCNVector3, fruit: Fruit?) {
        guard let name = fruit?.name else { return }
        
        // Only one dot showing on the scene
        if point != nil{
            point!.removeFromParentNode()
        }
        
        // Dot attributes, 366UIColor #95c2c3 from background
        let dot = SCNSphere(radius: 0.005)
        dot.materials.first?.diffuse.contents = UIColor(red: 0x95/255, green: 0xc2/255, blue: 0xc3/255, alpha: 1.0)
        
        // Add it to scene node
        let dotnode = SCNNode(geometry: dot)
        dotnode.position = position
        sceneView.scene.rootNode.addChildNode(dotnode)
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [.Y]
        dotnode.constraints = [billboardConstraint]
        
        point = dotnode
    }
    
    // ShowCard -> CardPlane(): initial the introduction card plane
    func CardPlane() -> SCNNode {
        // Initial plane
        let plane = SCNPlane(width: CardUI.Width, height: CardUI.Height)
        
        // Set card background for plane
        let CardBG = SCNMaterial()
        CardBG.diffuse.contents = "background.png"
        plane.firstMaterial = CardBG
        plane.cornerRadius = 0.02
        
        // Add plane to scene node
        self.planeNode = SCNNode(geometry: plane)
        return planeNode!
    }
    
    // ShowCard -> CardText(): initial the text info on card plane
    func CardText(string: String, scale: Float) -> SCNNode {
        // Set attributes
        let textGeometry = SCNText(string: string, extrusionDepth: 0.2)
        textGeometry.font = UIFont(name: "Arial", size: 2)
        textGeometry.firstMaterial!.diffuse.contents = UIColor.white
        
        // Add to scene node
        let txtNode = SCNNode(geometry: textGeometry)
        txtNode.scale = SCNVector3(scale, scale, scale)
        return txtNode
       }
    
    
    // ShowCard -> TextPosition(): initial the text position on card plane
    func TextPosition(text: SCNNode, card: SCNNode, heightLevel: Float) {
        let (BoundMin, BoundMax) = card.boundingBox
        let (TextBoundMin, TextBoundMax) = text.boundingBox
        
        // Set positopn
        text.position = card.position
        text.position.x = BoundMin.x + 0.5*((BoundMax.x-BoundMin.x)-((TextBoundMax.x-TextBoundMin.x)*CardUI.NameScale))
        text.position.y = BoundMax.y-heightLevel * CardUI.space
        
        // Add to scene node
        card.addChildNode(text)
    }
    
    // ShowCard -> CardPosition(): initial the card plane position on scene
    func CardPosition(_ card: SCNNode, _ position: SCNVector3) {
        card.position = position
        card.position.x += CardUI.cardPositionXOffset
        card.position.y += CardUI.cardPositionYOffset
    }
    
    // ShowCard on scene
    func ShowCard(position: SCNVector3, fruit: Fruit?){
        guard let name = fruit?.name else { return }
        guard let calories = fruit?.calories else { return }
        guard let tips = fruit?.tips else { return }
        
        let card = CardPlane()
        
        let FruitName = CardText(string: "Name: \(name)", scale: CardUI.NameScale)
        TextPosition(text: FruitName, card: card, heightLevel: 1.0)
        
        let FruitCalories = CardText(string: "Calories: \(calories)", scale: CardUI.CaloriesScale)
        TextPosition(text: FruitCalories, card: card, heightLevel: 2.0)
        
        let FruitTips = CardText(string: "Tips: \(tips)", scale: CardUI.TipsScale)
        TextPosition(text: FruitTips, card: card, heightLevel: 3.0)
        
        CardPosition(card, position)
        cardDictionary[name] = card
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        card.constraints = [billboardConstraint]

        self.card = card
        sceneView.scene.rootNode.addChildNode(card)

    }
}


