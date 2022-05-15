//
//  ViewController.swift
//  AutoFlowUI
//
//  Created by Felipe Campos on 2/28/22.
//

import Cocoa

@available(macOS 12.0, *)
class ViewController: NSViewController, NSComboBoxDelegate, NSGestureRecognizerDelegate {
    @IBOutlet weak var beatTapButton: NSButton!
    @IBOutlet weak var leftBarsView: NSScrollView!
    @IBOutlet var leftBarsTextView: NSTextView!
    @IBOutlet var middleSyllableTextView: NSTextView!
    @IBOutlet weak var rightRhythmView: NSScrollView! // for images generated in python - maybe clickable by pixel?
    // TODO: middle syllable view - syllables as buttons for merging - allow multi select and options etc. -- this is the meat for now
    // TODO: right image view? -- just notation - ideally buttons tho overlayed
    
    // https://www.raywenderlich.com/759-macos-controls-tutorial-part-1-2#toc-anchor-007 <-- NSComboBox tutorial for data sources etc.
    @IBOutlet weak var artistDropdown: NSComboBox!
    @IBOutlet weak var songDropdown: NSComboBox!
    
    @IBOutlet weak var annotationModeControl: NSSegmentedControl!
    
    @IBOutlet weak var loadBarsButton: NSButton!
    
    var isLight: Bool { NSApp.effectiveAppearance.name == NSAppearance.Name.aqua }
    var isDark: Bool { NSApp.effectiveAppearance.name == NSAppearance.Name.darkAqua }
    
    var artistMap: [String : String] = [:] // artist string --> artist id
    var artistSongMap: [String : [String : String]] = [:] // artist string --> songMap // TODO: have this be the default way of loading songs, such that clicking the artist doesn't have to query the server?
    var activeSongMap: [String : String] = [:] // song string --> song id
    
    var currentArtist: String = ""
    var currentSong: String = ""
    var currentSongProto: SongProto?
    
    var selectedSyllableRanges: [NSRange : SyllableProto] = [:]
    
    var syllableBeats: [SyllableProto?] = [] // use enum union type to represent syllable proto and or beat? or just make a wrapper (rapper lol) class
    
    let REST_SYMBOL: String = "§"
    
    /*
     Rendering:
     - show a meaningful ascii character for resets lol like a drum or sth idk
     
     */
    
    enum TappingMode {
        case None
        case Tapping
        case Editing
        case Aligning
    }
    
    enum AnnotationMode {
        case None
        case Syllabic
        case Beat
        case Rhymes
    }
    
    var annotationMode: AnnotationMode = .None
    
    var keyDownEventActive: Bool = false
    var tappingMode: TappingMode = .None // FIXME: start in None and then change with button
    var timeRef: Double? = nil
    var timeArray: [Double] = []
    
    func clearSlate(deselect: Bool = true) {
        leftBarsTextView.string = ""
        middleSyllableTextView.string = ""
        selectedSyllableRanges = [:]
        
        if (deselect) {
            activeSongMap = [:]
            songDropdown.removeAllItems()
            songDropdown.reloadData()
            songDropdown.deselectItem(at: songDropdown.indexOfSelectedItem)
            currentSong = ""
            
            artistMap = [:]
            artistDropdown.removeAllItems()
            artistDropdown.reloadData()
            artistDropdown.deselectItem(at: artistDropdown.indexOfSelectedItem)
            currentArtist = ""
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: keyDownEvent(event:))
        self.artistDropdown.delegate = self
        self.songDropdown.delegate = self
        
        getArtists()
        
        // TODO: scroll view can hold an image of a given size -- Abjad clickability (can we pass info over to hack this? like spacing or something)
        
        let tap = NSClickGestureRecognizer(target: self, action: #selector(clickResponse(recognizer:)))
        middleSyllableTextView.isEditable = false
        middleSyllableTextView.addGestureRecognizer(tap)
        
        annotationMode = .None
        annotationModeControl.selectedSegment = 0
        
        loadBarsButton.contentTintColor = .red
    }
    
    func annotateBeat(recognizer: NSClickGestureRecognizer) {
        /*
         1. Annotate successive syllables (command click for beat before)
         2. Update sensor field
         */
        
        let textView: NSTextView = middleSyllableTextView
        var commanded: Bool = false
        if let currentEvent = NSApp.currentEvent {
            print("click \(String(describing: currentEvent))")
            if (currentEvent.modifierFlags.contains(.command)) {
                print("commanded")
                commanded = true
            }
        }
        
        if recognizer.state == .ended {
            let location: CGPoint = recognizer.location(in: textView)
            let tapPosition = textView.characterIndexForInsertion(at: location)
            let startCharacter = NSRange(location: tapPosition, length: 0)
            let wordRange = textView.selectionRange(forProposedRange: startCharacter, granularity: .selectByWord)
            
            print(wordRange, wordRange.lowerBound, wordRange.upperBound)
            
            if let tappedSyllable = textView.attributedSubstring(forProposedRange: wordRange, actualRange: nil) {
                print(wordRange.lowerBound, wordRange.upperBound, tappedSyllable.string, tappedSyllable.string.count)
                if (tappedSyllable.string == " " || tappedSyllable.string == "\n") {
                    print("Got \(tappedSyllable.string.debugDescription), dipping.") // NOTE: should never happen -- hold on word for space before (or shift click)
                    return
                }
                
                let syllableText = textView.string
                let syllableIndex = syllableText.index(syllableText.startIndex, offsetBy: wordRange.lowerBound)
                let preText = syllableText.prefix(upTo: syllableIndex)
                
                let splitLines = preText.components(separatedBy: "\n")
                let barIndex = splitLines.count - 1

                let syllIndex = splitLines.last!.components(separatedBy: " ").count - 1
                
                if (commanded) {
                    // number of beats before or something (could have more than one before) - or maybe it just adds to index of previous? let's think about this representation - maybe sets the start of the syllable to be later ahhh ok this changes things
                    // could just click it twice you feel (need a good way to visualize though so editor knows)
                    
                    // could add a character that gets rendered as a rest
                    // also - may want to move away from this bars format, and just have one large chunk of lyrics with endlines...? what do you think? --> cuz it limits things to being same phrase and same line
                    
                    // scope out how this changes things
                    
                    var restProto = SyllableProto()
                    restProto.syllable = REST_SYMBOL
                    restProto.marked = true
                    
                    currentSongProto!.bars[barIndex].syllables.insert(restProto, at: syllIndex)
                } else {
                    // annotate this syllable (may need an intermediate representation, we'll see) --> think about how we do it handwritten
                    
                    /*
                     Mark syllable - later solve rest indexing (effectivelly a no-op syllable)
                     */
                    
                    print(currentSongProto!.bars[barIndex].syllables[syllIndex].marked)
                    if (currentSongProto!.bars[barIndex].syllables[syllIndex].marked) {
                        currentSongProto!.bars[barIndex].syllables[syllIndex].marked = false
                        if (isDark) {
                            print("DARK MODE \(NSAppearance.currentDrawing().name)")
                            textView.setTextColor(.white, range: wordRange)
                        } else {
                            print("LIGHT MODE: \(NSAppearance.currentDrawing().name)")
                            textView.setTextColor(.black, range: wordRange)
                        }
                    } else {
                        currentSongProto!.bars[barIndex].syllables[syllIndex].marked = true
                        print(currentSongProto!.bars[barIndex].syllables[syllIndex].marked)
                        textView.setTextColor(.blue, range: wordRange)
                    }
                }
            }
        }
    }
    
    func annotateRhyme(recognizer: NSClickGestureRecognizer) {
        print("Rhyme annotation not implemented")
    }
    
    func annotateSyllable(recognizer: NSClickGestureRecognizer) {
        let textView: NSTextView = middleSyllableTextView
        var commanded: Bool = false
        if let currentEvent = NSApp.currentEvent {
            print("click \(String(describing: currentEvent))")
            if (currentEvent.modifierFlags.contains(.command)) {
                print("commanded")
                commanded = true
            }
        }
        
        if recognizer.state == .ended {
            let location: CGPoint = recognizer.location(in: textView)
            let tapPosition = textView.characterIndexForInsertion(at: location)
            let startCharacter = NSRange(location: tapPosition, length: 0)
            let wordRange = textView.selectionRange(forProposedRange: startCharacter, granularity: NSSelectionGranularity.selectByWord)
            
            print(wordRange, wordRange.lowerBound, wordRange.upperBound)
            
            /*
            guard let textRange = textView.textContainer?.textLayoutManager?.textRange(for: NSTextSelection.Granularity.word, enclosing: tapPosition as! NSTextLocation) else { print("failed 1"); return }
            
            guard let rangeLength: Int = textView.textContentStorage?.offset(from: textRange.location, to: textRange.endLocation) else { print("failed 2"); return }
             */
            
            if let tappedSyllable = textView.attributedSubstring(forProposedRange: wordRange, actualRange: nil) {
                print(wordRange.lowerBound, wordRange.upperBound, tappedSyllable.string, tappedSyllable.string.count)
                if (tappedSyllable.string == " " || tappedSyllable.string == "\n") {
                    print("Got \(tappedSyllable.string.debugDescription), dipping.") // NOTE: should never happen -- hold on word for space before (or shift click)
                    return
                }
                
                let syllableText = textView.string
                let syllableIndex = syllableText.index(syllableText.startIndex, offsetBy: wordRange.lowerBound)
                let preText = syllableText.prefix(upTo: syllableIndex)
                
                let splitLines = preText.components(separatedBy: "\n")
                let barIndex = splitLines.count - 1

                let syllIndex = splitLines.last!.components(separatedBy: " ").count - 1
                print(syllIndex)
                
                
                let barProto = currentSongProto!.bars[barIndex]
                let syllableProto = barProto.syllables[syllIndex]
                print(syllableProto)
                
                // TODO: rename vars nicely
                
                if (tappedSyllable.string != syllableProto.syllable) {
                    print("ERROR: no match between tapped syllable \(tappedSyllable.string.debugDescription) and extracted syllable \(syllableProto.syllable), quitting.")
                    return
                }
                
                var alreadySelected: Bool = false
                var adjacentToSelected: Bool = selectedSyllableRanges.count == 0
                if (!commanded) {
                    adjacentToSelected = true
                    // consider: https://developer.apple.com/documentation/uikit/appearance_customization/supporting_dark_mode_in_your_interface
                    if (isDark) {
                        print("DARK MODE \(NSAppearance.currentDrawing().name)")
                        textView.setTextColor(.white, range: NSRange(location: 0, length: textView.textStorage!.length))
                    } else {
                        print("LIGHT MODE: \(NSAppearance.currentDrawing().name)")
                        textView.setTextColor(.black, range: NSRange(location: 0, length: textView.textStorage!.length))
                    }
                    // textView.setTextColor(.black, range: NSRange(location: 0, length: textView.textStorage!.length))
                    
                    alreadySelected = selectedSyllableRanges.keys.contains(wordRange)
                        
                    selectedSyllableRanges = [:]
                    if (alreadySelected) {
                        print("Current word already selected, dipping.")
                        return
                    }
                } else {
                    // check that selected word is adjacent to one of the other words
                    for _range in selectedSyllableRanges.keys {
                        if (_range.lowerBound - (wordRange.upperBound - 1) == 2 || wordRange.lowerBound - (_range.upperBound - 1) == 2) {
                            print("adjacent")
                            adjacentToSelected = true
                        } else {
                            print("not adjacent")
                            print(_range.lowerBound - wordRange.upperBound)
                            print(wordRange.lowerBound - _range.upperBound)
                        }
                        
                        if (selectedSyllableRanges[_range]!.parentWord.id != syllableProto.parentWord.id) {
                            print("Not same parent word")
                            adjacentToSelected = false
                        }
                    }
                }
                
                if (adjacentToSelected) {
                    textView.setTextColor(.red, range: wordRange)
                    selectedSyllableRanges[wordRange] = syllableProto
                }
            } else {
                print("failed to create attributed substring")
            }
        }
    }
    
    @objc func clickResponse(recognizer: NSClickGestureRecognizer) {
        switch annotationMode {
        case .None:
            print("No annotation mode set.")
        case .Syllabic:
            annotateSyllable(recognizer: recognizer)
        case .Beat:
            annotateBeat(recognizer: recognizer)
        case .Rhymes:
            annotateRhyme(recognizer: recognizer)
        }
    }
    
    func getSongFromComboBox() {
        if let selectedArtist = artistDropdown.objectValueOfSelectedItem as? String {
            if (selectedArtist != currentArtist) {
                currentArtist = selectedArtist
                getSongs(artist: currentArtist)
            }
            
            if let selectedSong = songDropdown.objectValueOfSelectedItem as? String {
                if (currentSong != selectedSong) {
                    currentSong = selectedSong
                    getSongProto(artist: currentArtist, song: currentSong)
                }
            }
        }
    }

    @IBAction func loadPressed(_ sender: NSButton) {
        getSongFromComboBox()
    }
    
    @IBAction func reloadPressed(_ sender: NSButton) {
        clearSlate()
        getArtists()
    }
    
    
    @IBAction func segmentedControlChanged(_ sender: NSSegmentedControl) {
        if (isDark) {
            print("DARK MODE \(NSAppearance.currentDrawing().name)")
            middleSyllableTextView.setTextColor(.white, range: NSRange(location: 0, length: middleSyllableTextView.textStorage!.length))
        } else {
            print("LIGHT MODE: \(NSAppearance.currentDrawing().name)")
            middleSyllableTextView.setTextColor(.black, range: NSRange(location: 0, length: middleSyllableTextView.textStorage!.length))
        }
        
        switch annotationModeControl.selectedSegment {
        case 0:
            annotationMode = .None
        case 1:
            annotationMode = .Syllabic
        case 2:
            annotationMode = .Beat
            // when this gets set --> save syllabic parsing
            // every time a beat gets set --> write proto to file (with substrate hash)
            // TODO: load and render currently annotated beats (and rests) --> will have to handle rest annotation during indexing look up
            var barIndexStart: Int = 0
            for bar in currentSongProto!.bars {
                var syllableIndexStart: Int = 0
                for syllable in bar.syllables {
                    if syllable.marked {
                        let syllableRange = NSRange(location: barIndexStart + syllableIndexStart, length: syllable.syllable.count)
                        middleSyllableTextView.setTextColor(.blue, range: syllableRange)
                    }
                    syllableIndexStart += syllable.syllable.count + 1 // space
                }
                
                barIndexStart += bar.rawSyllables.count + 1 // endline... may be off by 1
                
                // TODO: totally move away from rawSyllables --> just autogenerate from raw repr and do the math (can ignore rests if you desire for other reprs)
                
                // it's not that much slower and I'm not sure I see the benefits since we can always auto-generate (per line or for range of lines helper fns or something in core.py)
                
                /*
                 NEXT: rests implementation and rendering (and deleting) -- requires generation from repeated proto contents
                 
                 Once rests are implemented and tested:
                 - Saving on server for state-ful representation and loading
                 - Line by line overriding for editing and writing songs
                 
                 - Simple statistics with linear interpolation (e.g. syllables between beats on average with deviation per line per song etc., syllabic velocity throughout song, etc. -- look at notes!!!)
                 
                 - Tapping (quantized - defining a certain BPM --> subsequently speeding up and aligning with song to play with and show simple piano roll!!! then we start to get into interesting deep learning / module automation territory)
                 
                 - Piano roll from drums can start getting overlayed in interesting ways (ehh)
                 - Think about ways this lets you go deeper from a production standpoint --> rhythm and rhyme schemes --> wordplay is another level of representation --> style --> storytelling --> else are out of the soul
                 */
            }
        case 3:
            annotationMode = .Rhymes
            // when this gets set --> save syllabic parsing
            // every time a rhyme gets set --> write proto to file (with substrate hash)
        default:
            print("FATAL ERROR")
        }
        
        print("Annotation mode set to \(annotationMode)")
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        getSongFromComboBox()
    }
    
    // MARK: HTTP Server Calls
    
    func getArtists() {
        let request = ServerUtils.getRequest(domain: ServerUtils.getServerDomain(), endpoint: "get_artists")
        
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                let responseStatus = ServerUtils.getStatus(httpResponse: httpResponse)
                switch responseStatus {
                case .OK:
                    do {
                        let json = try JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                        print("Got evaluation response: \(json)")
                        if let artists = json["artists"] as? [String : String] {
                            print("Found artists")
                            
                            DispatchQueue.main.async { [self] in
                                artistMap = [:]
                                artistDropdown.removeAllItems()
                                for (artistId, artistName) in artists {
                                    artistMap[artistName] = artistId
                                    artistDropdown.addItem(withObjectValue: artistName)
                                }
                                artistDropdown.reloadData()
                            }
                        }
                    } catch {
                        print("Error when parsing JSON response: \(error.localizedDescription)")
                    }
                default:
                    print("Bad status code: \(responseStatus)")
                }
            } else {
                print("Invalid HTTP response.")
            }
        }
        task.resume()
    }
    
    // TODO: helper GET and POST methods that return optional response and boolean and/or code
    
    func getSongs(artist: String) {
        if let artistId = artistMap[artist] {
            let request = ServerUtils.getRequest(domain: ServerUtils.getServerDomain(), endpoint: "get_songs", args: ["artist" : artistId])
            
            let task = URLSession.shared.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let responseStatus = ServerUtils.getStatus(httpResponse: httpResponse)
                    switch responseStatus {
                    case .OK:
                        do {
                            let json = try JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                            print("Got evaluation response: \(json)")
                            if let artists = json["songs"] as? [String : String] {
                                print("Found songs")
                                // TODO: maybe make these protod? repeated fields etc. and backend handles all the population etc.
                                DispatchQueue.main.async { [self] in
                                    clearSlate(deselect: false)
                                    activeSongMap = [:]
                                    songDropdown.removeAllItems()
                                    for (songId, songName) in artists {
                                        activeSongMap[songName] = songId
                                        songDropdown.addItem(withObjectValue: songName)
                                    }
                                    songDropdown.reloadData()
                                    songDropdown.deselectItem(at: songDropdown.indexOfSelectedItem)
                                }
                            }
                        } catch {
                            print("Error when parsing JSON response: \(error.localizedDescription)")
                        }
                    default:
                        print("Bad status code: \(responseStatus)")
                    }
                } else {
                    print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    func getSongProto(artist: String, song: String) {
        if let artistId = artistMap[artist], let songId = activeSongMap[song] {
            let request = ServerUtils.getRequest(domain: ServerUtils.getServerDomain(), endpoint: "get_song_proto", args: ["artist" : artistId, "song" : songId])
            
            let session = URLSession.shared
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let responseStatus = ServerUtils.getStatus(httpResponse: httpResponse)
                    switch responseStatus {
                    case .OK:
                        do {
                            let song_proto = try SongProto(serializedData: data!)
                            self.currentSongProto = song_proto
                            
                            DispatchQueue.main.async { [self] in
                                leftBarsTextView.string = ""
                                middleSyllableTextView.string = ""
                                
                                print("YOYOYO")
                                for bar in song_proto.bars {
                                    print(bar.rawWords)
                                    leftBarsTextView.string += bar.rawWords + "\n"
                                    middleSyllableTextView.string += bar.rawSyllables + "\n"
                                }
                            }
                        } catch {
                            print("Error when parsing JSON response: \(error.localizedDescription) \(String(describing: response))")
                        }
                    default:
                        print("Bad status code: \(responseStatus)")
                    }
                } else {
                    print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    func updateGlobalOverride(artist: String, song: String, overrideWordProto: WordProto, regenSong: Bool = true, force: Bool = false) {
        if let artistId = artistMap[artist], let songId = activeSongMap[song] {
            let request = ServerUtils.postRequest(domain: ServerUtils.getServerDomain(), endpoint: "update_global_override", args: ["artist" : artistId, "song" : songId, "force" : String(force)], bodyData: try! overrideWordProto.serializedData(), dataType: ServerUtils.PROTOBUF_ATTACHMENT)
            
            let task = URLSession.shared.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let responseStatus = ServerUtils.getStatus(httpResponse: httpResponse)
                    switch responseStatus {
                    case .OK:
                        print("Successfully updated.")
                        if regenSong {
                            self.getSongProto(artist: artist, song: song)
                        }
                    case .MULTIPLE_OPTIONS:
                        if (force) {
                            print("Hmmm...")
                        } else {
                            DispatchQueue.main.async {
                                let forceUpdateAlert = NSAlert()
                                forceUpdateAlert.messageText = "This word was found in an existing override, force update?"
                                forceUpdateAlert.addButton(withTitle: "Force Update")
                                forceUpdateAlert.addButton(withTitle: "Cancel")
                                forceUpdateAlert.alertStyle = .informational
                                
                                let userResponse = forceUpdateAlert.runModal()
                                
                                let forceUpdate = userResponse == .alertFirstButtonReturn
                                if (forceUpdate) {
                                    self.updateGlobalOverride(artist: artist, song: song, overrideWordProto: overrideWordProto, regenSong: regenSong, force: true)
                                }
                            }
                        }
                    default:
                        print("Bad status code: \(responseStatus)") // TODO: also print response details
                    }
                } else {
                  print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    // TODO: one function with truth value so we're not replicating too much code
    
    func updateLocalOverride(artist: String, song: String, overrideWordProto: WordProto, regenSong: Bool = true, force: Bool = false) {
        if let artistId = artistMap[artist], let songId = activeSongMap[song] {
            let request = ServerUtils.postRequest(domain: ServerUtils.getServerDomain(), endpoint: "update_local_override", args: ["artist" : artistId, "song" : songId, "force" : String(force)], bodyData: try! overrideWordProto.serializedData(), dataType: ServerUtils.PROTOBUF_ATTACHMENT)
            
            let task = URLSession.shared.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let responseStatus = ServerUtils.getStatus(httpResponse: httpResponse)
                    switch responseStatus {
                    case .OK:
                        print("Successfully updated.")
                        if regenSong {
                            self.getSongProto(artist: artist, song: song)
                        }
                    case .MULTIPLE_OPTIONS:
                        if (force) {
                            print("Hmmm...")
                        } else {
                            DispatchQueue.main.async {
                                let forceUpdateAlert = NSAlert()
                                forceUpdateAlert.messageText = "This word was found in an existing override, force update?"
                                forceUpdateAlert.addButton(withTitle: "Force Update")
                                forceUpdateAlert.addButton(withTitle: "Cancel")
                                forceUpdateAlert.alertStyle = .informational
                                
                                let userResponse = forceUpdateAlert.runModal()
                                
                                let forceUpdate = userResponse == .alertFirstButtonReturn
                                if (forceUpdate) {
                                    self.updateLocalOverride(artist: artist, song: song, overrideWordProto: overrideWordProto, regenSong: regenSong, force: true)
                                }
                            }
                        }
                    default:
                        print("Bad status code: \(responseStatus)")
                    }
                } else {
                  print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    // MARK: User Input Event Handling
    
    func keyDownEvent(event: NSEvent) -> NSEvent {
        if (keyDownEventActive) { // TODO: check if this fucks with timing stuff... shouldn't - also prolly not using that yet (could be cool to use for percussion flow type stuff - may be better way to capture this kind of input for timing too... ask X
            print("Key down event active, ignoring.")
            return event
        }
        
        keyDownEventActive = true
        
        print("Key down \(event.keyCode)")
        if (annotationMode == .Syllabic) {
            if (event.keyCode == 36) { // enter key
                editSyllabicParsing()
            }
        } else if (tappingMode == .Tapping) {
            // Key codes: https://stackoverflow.com/questions/28012566/swift-osx-key-event
            if (event.keyCode == 49) { // space bar
                // call wrapper function for handling timing / beat generation
                beatRecord() // TODO: make sure this is consistent
            } // TODO: get up and down timing... for start and end of MIDI events
        } else {
            print(timeArray)
        }
        
        keyDownEventActive = false
        
        return event
    }

    @IBAction func beatButtonTapped(_ sender: NSButton) {
        // maybe just change modes for now and color changes
        switch tappingMode {
        case .None:
            leftBarsTextView.isEditable = false
            tappingMode = .Tapping
            beatTapButton.contentTintColor = NSColor.blue
            break
        case .Tapping:
            leftBarsTextView.isEditable = true
            tappingMode = .None
            beatTapButton.contentTintColor = NSColor.gray
            break
        case .Editing:
            break
        case .Aligning:
            break
        }
    }
    
    /**
     Helper function used as callback for recording syllabic rhythm. Assumption is that this is called on successive taps on the time that a syllable is spoken.
     
     Some other modes could include selecting only quarter notes, but this methodology would likely not allow for that and would require simply selecting the syllables themselves.  This could then be used on top of that (almost as bumper rails in bowling) as a hard reset in case we see drift over time.
     
     - note: Could this be Kalman filtered hahaha.
     */
    func beatRecord(senderTimestamp: Double? = nil) {
        var currTimeInterval: Double = Date().timeIntervalSince1970
        if let t = senderTimestamp {
            print("Time sent in.")
            currTimeInterval = t
        } // accuracy of this? does sender report a tapped time?
        
        if (timeRef == nil) {
            timeRef = currTimeInterval
            timeArray.append(0)
        } else {
            timeArray.append(currTimeInterval - timeRef!)
        }
        
        print(timeArray)
    }
    
    let WORD_LEVEL_SYLLABLE_EDITING = false
    
    func editSyllabicParsing(force: Bool = false) {
        if (selectedSyllableRanges.count > 0) {
            print("selected syllables: \(selectedSyllableRanges)")
            // get syllables
            var totalSyllables = ""
            var parentWordProto = WordProto()
            
            if (!self.WORD_LEVEL_SYLLABLE_EDITING) {
                let sortedRanges: [NSRange] = selectedSyllableRanges.keys.sorted(by: {$0.lowerBound < $1.lowerBound})
                
                var sortedSyllables: [SyllableProto] = [] // do we need this - probs not outside debugging print below
                totalSyllables = ""
                parentWordProto = WordProto()
                for (sortedRange) in sortedRanges {
                    let s = selectedSyllableRanges[sortedRange]!
                    sortedSyllables.append(s)
                    totalSyllables += (s.syllable + " ")
                    if parentWordProto.hasID {
                        assert(parentWordProto.id == s.parentWord.id)
                    } else {
                        parentWordProto.id = s.parentWord.id
                        parentWordProto.word = s.parentWord.word
                    }
                }
                
                totalSyllables.remove(at: totalSyllables.index(before: totalSyllables.endIndex)) // removes last space
            
                print(sortedRanges)
                print(sortedSyllables)
            } else {
                // TODO: select by word editing (either in word view or if you select a given syllable yeah)
                // NOTE: for now just select every syllable lol
            }
            
            print(totalSyllables)
            
            let syllabicParsingEditingView = NSAlert()
            syllabicParsingEditingView.messageText = "Syllable Parser Override"
            if !force {
                syllabicParsingEditingView.informativeText = "Edit the text below to modify the syllable parsing cache"
            } else {
                syllabicParsingEditingView.informativeText = "Are you sure you want to "
            }
            syllabicParsingEditingView.addButton(withTitle: "Song-Local Update")
            syllabicParsingEditingView.addButton(withTitle: "Global Update")
            syllabicParsingEditingView.addButton(withTitle: "Cancel")
            syllabicParsingEditingView.alertStyle = .informational
            
            let syllabicParsedText = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            syllabicParsedText.stringValue = totalSyllables
            
            syllabicParsingEditingView.accessoryView = syllabicParsedText
            let userResponse = syllabicParsingEditingView.runModal()
            
            let localUpdate = userResponse == .alertFirstButtonReturn
            let globalUpdate = userResponse == .alertSecondButtonReturn
            
            if (globalUpdate || localUpdate) {
                print("Here is new text: \(syllabicParsedText.stringValue)")
                
                let syllables = syllabicParsedText.stringValue.components(separatedBy: " ")
                for syllable in syllables {
                    if syllable == "" {
                        print("Empty, ignoring")
                        continue
                    }
                    
                    var syllableProto = SyllableProto()
                    syllableProto.syllable = syllable
                    parentWordProto.syllables.append(syllableProto)
                }
                
                if localUpdate {
                    updateLocalOverride(artist: currentArtist, song: currentSong, overrideWordProto: parentWordProto)
                } else if globalUpdate {
                    updateGlobalOverride(artist: currentArtist, song: currentSong, overrideWordProto: parentWordProto)
                } // else if wordLevelUpdate -- separate implementation
            } else {
                print("Canceled")
            }
        }
    }
}
