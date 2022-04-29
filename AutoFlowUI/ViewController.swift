//
//  ViewController.swift
//  AutoFlowUI
//
//  Created by Felipe Campos on 2/28/22.
//

import Cocoa

/*
 TODO: UI for typing up songs (creation mode) and then freezing and doing syllabic analysis - what makes the most sense in the first order
 
 to start, let's assume song is fully typed up from backend and we're just pulling syllabic analysis
 
 TODO: Think about basic UI for selecting through different syllables, or for rendering beats / music (what backend support do we need there) -- let's think about this in the philosophy of human in the loop automation (define the loop, whether it's correction or prior setting at any level)
 
 TODO: 3 views, basic text view (can lock), syllable view, and music notation view
 
 TODO: Play music button (what preprocessing do we need -- BPM analysis / input and start locations for each 4x4 measure -- don't worry about cases like alphabet aerobics)
 
 --
 
 TODO: IMPORTANT DESIGN DECISION
 
 Just annotate the metronome for now, this is easy and chill and already allows for basic statistics (and is a good first pass)
 
 Build a simple UI around this, we can make a branch for more complicated shit
 
 Mighty Mos Def - Mathematics mode (can go more fine from there)
 
 Can literally just click syllables after freezing --> also doesn't require the one line is one measure / bar assumption! this actually constrains that for us in a much much nicer fashion
 
 Syllable Errors: would be nice to have text to audio alignment - this is definitely possible
 */

@available(macOS 12.0, *)
class ViewController: NSViewController, NSComboBoxDelegate, NSGestureRecognizerDelegate {
    @IBOutlet weak var beatTapButton: NSButton!
    @IBOutlet weak var leftBarsView: NSScrollView!
    @IBOutlet var leftBarsTextView: NSTextView!
    @IBOutlet var middleSyllableTextView: NSTextView!
    @IBOutlet weak var rightRhythmView: NSScrollView!
    // TODO: middle syllable view - syllables as buttons for merging - allow multi select and options etc. -- this is the meat for now
    // TODO: right image view? -- just notation - ideally buttons tho overlayed
    
    // https://www.raywenderlich.com/759-macos-controls-tutorial-part-1-2#toc-anchor-007 <-- NSComboBox tutorial for data sources etc.
    @IBOutlet weak var artistDropdown: NSComboBox!
    @IBOutlet weak var songDropdown: NSComboBox!
    
    @IBOutlet weak var loadBarsButton: NSButton!
    
    var isLight: Bool { NSApp.effectiveAppearance.name == NSAppearance.Name.aqua }
    var isDark: Bool { NSApp.effectiveAppearance.name == NSAppearance.Name.darkAqua }
    
    var artistMap: [String : String] = [:] // artist string --> artist id
    var artistSongMap: [String : [String : String]] = [:] // artist string --> songMap // TODO: have this be the default way of loading songs, such that clicking the artist doesn't have to query the server?
    var activeSongMap: [String : String] = [:] // song string --> song id
    
    var currentArtist: String = ""
    var currentSong: String = ""
    var currentSongProto: SongProto? // TODO: song proto should store artist information as well...??? like song name etc. oh shit we can make the metadata a proto hahaaaa hell yeah, that's separate maybe tho idk
    
    var server_url: String = "autoflow.ngrok.io"
    
    var selectedSyllableRanges: [NSRange : SyllableProto] = [:] // TODO: move this logic to another class or something - for now massive view controller is fine hahah just might get confusing
    
    // TODO: build super class representation of the Text View / Collection view
    
    // 1. Left Text view: should render line by line each bar (split by endlines)
    // 2. Right Collection (?) view: should store each 4x4 meter bar as sheet music and a lyrical chart with syllables below (NOTE: may require some vertical spacing to allow alignment with left text view)
    
    // TODO: install music kit -- maybe not necessary with Abjad
    
    // First demo: tapping and getting times back
    
    /*
     Tapping modes:
        1. Testing (like just dicking around on the beat)
        2. Editing (going over again in some manual editing mode)
        3. Aligning (aligning to syllables correctly - related to editing)
     */
    
    enum TappingMode {
        case None
        case Tapping
        case Editing
        case Aligning
    }
    
    var keyDownEventActive: Bool = false
    var syllableEditing: Bool = false
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
        
        // TODO: analyze button that computes and reloads syllabic annotations once you've written a song
        // TODO: JSON response contains separate syllables field, and maybe separate annotations field for rhythm / pitch / duration / etc.
        // think about post-annotation vs. live writing - git freezing??? like a docker container - lower layers rebuild upper - but we can still learn some things...
        
        // localize which word was tapped in uneditable view and merge / split accordingly (we can figure out several workflows for this, single popup asking to merge or split -- can have other buttons for merge or split mode --> then after you ask if you want to publish this to a word-specific (...how lol - requires lyric freezing) or local (default) or global override --> then server checks whether single or multi syllabic, adds correspondingly, and then syllable class takes in a local_override object that handles this!)
        
        // once you have this set up -- we can start thinking about basic annotation
        // bpm | beat base alignment are two most important things
        
        // another tapping mode for annotation can just be tapping the syllable that falls on the quarter beat in each measure / bar (what's the difference?)
        
        loadBarsButton.contentTintColor = .red
    }
    
    @objc func clickResponse(recognizer: NSClickGestureRecognizer) {
        let textView: NSTextView = middleSyllableTextView
        var commanded: Bool = false
        if let currentEvent = NSApp.currentEvent {
            print("click \(String(describing: currentEvent))")
            if (currentEvent.modifierFlags.contains(.command)) {
                print("commanded")
                commanded = true
                // ok sick we can now stitch together chosen syllables (they must be adjacent though or it breaks)
                // usually workflow for truly janked ones will be stitch then break
                // though - we could also provide a UI for them to just manually type in their own new annotation - must keep same letters tho or will break (remove spaces from both and check)
                // this is actually likely the way to do this
                // command click to select multiple on same line
                // otherwise just regular click - edit popup text box shows up and you edit within constraint that we allow
                // then we provide option to set for this word only, song global, artist global, or global global
                
                /*
                 HIGH LEVEL: What does this allow us? A clean syllabic completion interface that feeds back into the song representation, this provides us with a frozen and clear syllabic template atop which we can begin analyzing the rhythmic composition of songs based on their syllabic primitives
                 
                 From there we can start to talk about syllabic velocity, density, (rhyme schemes), and other parameters of flow from a tangible perspective
                 
                 Soon we will be in the realm of being able to sort and discuss by song, album, artist, generation and make quantifiable statements about the distributions of their parameters of flow, as well as specific analysis as to what makes certain patterns of rhythm and pitch overlaid on the beat so special
                 
                 What's blocking us right now?
                 - Lack of a cohesive serialized representation of these songs
                    - Simple solution: For now, just pickle everything with a version and latest symlink
                 - A sense of BPM, how to work within 4x4 meter based on timings, as well as starts of each measure (and whether we are sometimes overlapping into other measures even within the same "bar")
                    - Simple Solution: For now, only annotate syllables that fall on the beat
                 
                 What are we missing?
                 - A flow and interface for producers and writers (we are punting this problem)
                 
                 Immediate next steps:
                 1. Finish interface for merging and splitting (e.g. general editing of syllables on the frontend) --> maybe original generation should always be kept? and you can modify overrides manually on backend for now
                 2. Complete backend component of receiving these corrections
                    a. Consider also completing backend component of receiving song updates (I would prefer some basic version control here in case we delete stuff L)
                 3. Annotation:
                    a. Beat clicking: Music mode allows for beat clicking --> build simple serializable representation for that as a start --> this can let you start working on other problems yea
                    b. Tapping: Start doing basic renderings and real-time (Websocket both ways) tapping updates and renderings (even if on "backend" for now - it's on the same laptop lol) of the music
                        - (A. could even be a precursor to tapping mode????) Especially if we mark the 0th? idk i still think tapping requires some work - first tap is 0th with a different key like s, and rest are spaces, unless space is tapped immediately? nah will be confusing we can use like no-op for nothing and s for on first syllable and space for everything else
                 
                 Important but minor things!:
                 - Keep workflow checks (e.g. editing mode cancels if *old* / no syllables, annotation mode (tapping or otherwise) only works when editing is off, etc.)
                 */
            }
        }
        
        if (!syllableEditing) {
            print("Not in syllable editing mode, dipping.")
            // TODO: this should clear state - again proper MVC logic will make this hella easy lol - at some point we should do that refactor - just first get basic logic down first - once we see diminishing returns with desirable functionality we can git commit and refactor checking same functionality
            return
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
                if (tappedSyllable.string == " ") {
                    print("Got space, dipping.") // NOTE: should never happen -- hold on word for space before (or shift click)
                    return
                }
                
                // TODO: syllable proto extraction
                
                // 1. find # endlines before wordRange == barproto index
                let syllableText = textView.string
                let syllableIndex = syllableText.index(syllableText.startIndex, offsetBy: wordRange.lowerBound)
                let preText = syllableText.prefix(upTo: syllableIndex)
                
                let splitLines = preText.components(separatedBy: "\n")
                let barIndex = splitLines.count - 1
                
                let syllLine = splitLines.last!.components(separatedBy: " ")
                let syllIndex = syllLine.count - 1 // NOTE: for some reason you get a "" at the end of the list
                print(barIndex, syllIndex)
                
                let barProto = currentSongProto!.bars[barIndex]
                print(barProto)
                let syllableProto = barProto.syllables[syllIndex]
                print(syllableProto)
                
                // TODO: rename vars nicely
                
                // 2. get index of last endline
                
                // 3. number of words (spaces + 1) (-1 for index so just number of spaces lol) since last endline == syllable proto index
                
                // get syllable proto and check string equality --> add parent word check and add syllable (with wordRange for sorting later) to selectedSyllablesRanges -- now with new value type and same key type
                
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
                    
                    // TODO: start adding logic for passing back improved syllabic information
                    
                    /*
                     Step 1. For global overrides, validate serializable version (even if just simple pickle file or whatever - load, check existence, add, and write)
                     Step 2. Start creating local overrides, per song is fine for now
                     Step 3. Create method where we can automatically generate (or fix) the default file structure for a song (we can maybe stick with v0 verse structure for now and if we do big refactors we copy everything over to a v1)
                     */
                }
                
                // TODO: show callback with index and description of syllable or word (just syllable for now, we can do rhymes later!!!)
                
                /*
                 Features:
                 - Edit mode (using switch) for syllables allows you to edit
                 - You can merge split / etc.
                 - Ideally you can undo or have a baseline to go back to (git history, no redos tho lol)
                 - Could use the Undo Manager for this!
                 - CMD + click builds list of adjacent syllables (in a given line) and highlights them red (attributed text?)
                 - Might be worth keeping a reference to the parent word in the syllable object representation on the backend
                 
                 - You need to freeze this at some point though yeah
                 - Let's keep it simple for now -- no git, just confident freezing to get to the next stage lol
                 - We can think about the recursive editing process later (assuming syllabic parsing works well, at least 1 <-> 2 is smooth, issue is 3 get's semi fucked by that, could maybe only wipe line by line if we edit hmmmmm...)
                 */
                
                // first annotation pass - syllables (or spaces) that fall on the beat!!! - nice we can get spaces easily lol thank god
            } else {
                print("failed to create attributed substring")
            }
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
                    // getSong(artist: currentArtist, song: currentSong)
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
    
    
    @IBAction func editModeSwitched(_ sender: NSSwitch) {
        syllableEditing = !syllableEditing
        print("Syllable Editing: \(syllableEditing)")
    }
    
    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    
    func comboBoxSelectionDidChange(_ notification: Notification) {
        getSongFromComboBox()
    }
    
    func getArtists() {
        let url: URL? = URL(string: "https://\(server_url)/get_artists")
                
        let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let request = MutableURLRequest(url: url! as URL, cachePolicy: cachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "GET"
        
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                print("Code \(status)")
                if status == 200 { // OK
                    do {
                        let json = try JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                        print("Got evaluation response: \(json)")
                        if let artists = json["artists"] as? [String : String] {
                            print("Found artists")
                            
                            // TODO: consider just returning this value or setting it as a data source / dictionary somewhere that we can easily pull from (i.e. for name --> id mapping)
                            // TODO: query for songs on this: https://stackoverflow.com/questions/34937795/nscombobox-getget-value-on-change
                            // TODO: get song itself with same method -- need to return a good representation -- task for tonight
                            
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
                } else {
                    print(String(data: data!, encoding: .utf8) ?? "Not Found (Failed to decode response as string)") // TODO: should be detected client side?? give option to overwrite
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
            let url: URL? = URL(string: "https://\(server_url)/get_songs?artist=\(artistId)")
                    
            let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
            let request = MutableURLRequest(url: url! as URL, cachePolicy: cachePolicy, timeoutInterval: 10.0)
            request.httpMethod = "GET"
            
            let session = URLSession.shared
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    print("Code \(status)")
                    if status == 200 { // OK
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
                    } else {
                        print(String(data: data!, encoding: .utf8) ?? "Not Found (Failed to decode response as string)") // TODO: should be detected client side?? give option to overwrite
                    }
                } else {
                    print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    func getSong(artist: String, song: String) { // NOTE: Deprecated
        if let artistId = artistMap[artist], let songId = activeSongMap[song] {
            let url: URL? = URL(string: "https://\(server_url)/get_song?artist=\(artistId)&song=\(songId)")
                    
            let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
            let request = MutableURLRequest(url: url! as URL, cachePolicy: cachePolicy, timeoutInterval: 10.0)
            request.httpMethod = "GET"
            
            let session = URLSession.shared
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    print("Code \(status)")
                    if status == 200 { // OK
                        do {
                            let json = try JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                            print("Got evaluation response: \(json)")
                            if let result = json["contents"] as? String {
                                print(result)
                                DispatchQueue.main.async { [self] in
                                    leftBarsTextView.string = result
                                }
                            }
                            
                            if let result = json["syllables"] as? String {
                                print(result)
                                DispatchQueue.main.async { [self] in
                                    middleSyllableTextView.string = result
                                    // TODO: receive proto'd results --> set bars proto
                                    // TODO: callback that populates views with proto contents --> clicking a syllable gets its index in syllables array, gets parent word (and idx, checks it's the same for all -- this should happen live -- updates proto and sends back)
                                }
                            } else {
                                print("No saved syllabic analysis. Skipping.")
                            }
                        } catch {
                            print("Error when parsing JSON response: \(error.localizedDescription)")
                        }
                    } else {
                        print(String(data: data!, encoding: .utf8) ?? "Not Found (Failed to decode response as string)") // TODO: should be detected client side?? give option to overwrite
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
            let url: URL? = URL(string: "https://\(server_url)/get_song_proto?artist=\(artistId)&song=\(songId)")
                    
            let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
            let request = MutableURLRequest(url: url! as URL, cachePolicy: cachePolicy, timeoutInterval: 10.0)
            request.httpMethod = "GET"
            
            let session = URLSession.shared
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    print("Code \(status)")
                    if status == 200 { // OK
                        do {
                            let song_proto = try SongProto(serializedData: data!)
                            self.currentSongProto = song_proto // !!
                            // print("Got song proto: \(song_proto)")
                            
                            // sweeet this works -- now i guess we just need helper functions for populating (maybe python side just adds them)
                            
                            DispatchQueue.main.async { [self] in
                                // TODO: functions for populating views with relevant data from song proto (raw text actually seems to be important still.... with \ns and all)
                                leftBarsTextView.string = song_proto.words // TODO: next, start devving on this and see how currentSongProto is helpful and if indexing isn't complicated and makes it easy to access syllable objects (and their parent words -- id is used just for checking if valid merge / split neighbors, as well as for passing back override objects... that is an important next step to scope out)
                                // NOTE: high level, once you have syllabic parsing done, we can start thinking of some cooler stuff like what you've written down... annotating beat stresses provides a good prior on timing etc... some deep learning stuff to work on fs
                            }
                            
                            DispatchQueue.main.async { [self] in
                                // TODO: same as above but with syllables and allowing for tracking of indices and specifically which syllable you done tapped etc. (likely just by line index and syllable index...?)
                                middleSyllableTextView.string = song_proto.syllables
                                // TODO: receive proto'd results --> set bars proto
                                // TODO: callback that populates views with proto contents --> clicking a syllable gets its index in syllables array, gets parent word (and idx, checks it's the same for all -- this should happen live -- updates proto and sends back)
                            }
                        } catch {
                            print("Error when parsing JSON response: \(error.localizedDescription) \(response)")
                        }
                    } else {
                        print(String(data: data!, encoding: .utf8) ?? "Not Found (Failed to decode response as string)") // TODO: should be detected client side?? give option to overwrite
                    }
                } else {
                    print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    func runSyllabicAnalysis(artist: String, song: String) {
        if let artistId = artistMap[artist], let songId = activeSongMap[song] {
            let url: URL? = URL(string: "https://\(server_url)/analyze_song?artist=\(artistId)&song=\(songId)")
                    
            let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
            let request = MutableURLRequest(url: url! as URL, cachePolicy: cachePolicy, timeoutInterval: 10.0)
            request.httpMethod = "GET"
            
            let session = URLSession.shared
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                if let httpResponse = response as? HTTPURLResponse {
                    let status = httpResponse.statusCode
                    print("Code \(status)")
                    if status == 200 { // OK
                        do {
                            let json = try JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                            print("Got evaluation response: \(json)")
                            if let result = json["syllables"] as? String {
                                print(result)
                                DispatchQueue.main.async { [self] in
                                    middleSyllableTextView.string = result
                                }
                            }
                        } catch {
                            print("Error when parsing JSON response: \(error.localizedDescription)")
                        }
                    } else {
                        print(String(data: data!, encoding: .utf8) ?? "Not Found (Failed to decode response as string)") // TODO: should be detected client side?? give option to overwrite
                    }
                } else {
                    print("Invalid HTTP response.")
                }
            }
            task.resume()
        }
    }
    
    
    @IBAction func runAnalysis(_ sender: Any) { // TODO: delete this button
        runSyllabicAnalysis(artist: currentArtist, song: currentSong)
    }
    
    // TODO: some point soon we should do a pseudo-MVC refactor to make things easier - this will involve a day's worth of design, Friday?
    
    func keyDownEvent(event: NSEvent) -> NSEvent {
        if (keyDownEventActive) { // check if this fucks with timing stuff... shouldn't - also prolly not using that yet (could be cool to use for percussion flow type stuff - may be better way to capture this kind of input for timing too... ask X
            print("Key down event active, ignoring.")
            return event
        }
        
        keyDownEventActive = true
        
        print("Key down \(event.keyCode)")
        if (syllableEditing) {
            if (event.keyCode == 36) { // enter key
                if (selectedSyllableRanges.count > 0) {
                    print("selected syllables: \(selectedSyllableRanges)")
                    // get syllables
                    let sortedRanges: [NSRange] = selectedSyllableRanges.keys.sorted(by: {$0.lowerBound < $1.lowerBound})
                    
                    
                    var sortedSyllables: [SyllableProto] = []
                    var totalSyllables = ""
                    for (sortedRange) in sortedRanges {
                        let s = selectedSyllableRanges[sortedRange]!
                        sortedSyllables.append(s)
                        totalSyllables += (s.syllable + " ")
                    }
                    
                    totalSyllables.remove(at: totalSyllables.index(before: totalSyllables.endIndex)) // removes last space
                    
                    print(sortedRanges)
                    print(sortedSyllables)
                    print(totalSyllables)
                    
                    let syllablicParsingEditingView = NSAlert()
                    syllablicParsingEditingView.messageText = "Syllable Parser Override"
                    syllablicParsingEditingView.informativeText = "Edit the text below to modify the syllable parsing cache"
                    syllablicParsingEditingView.addButton(withTitle: "Ok")
                    syllablicParsingEditingView.addButton(withTitle: "Cancel")
                    syllablicParsingEditingView.alertStyle = .informational
                    
                    let syllabicParsedText = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                    syllabicParsedText.stringValue = totalSyllables
                    
                    syllablicParsingEditingView.accessoryView = syllabicParsedText
                    let userResponse = syllablicParsingEditingView.runModal()
                    
                    if (userResponse == .alertFirstButtonReturn) {
                        print("Here is new text: \(syllabicParsedText.stringValue)")
                    } else {
                        print("Canceled")
                    }
                    
                    // show standard popup for editing syllables (when clicking, need to check that they are part of same parent word)
                    
                    // syllable editing popup --> shows syllables and allows just raw editing as you like, then returns parent word and those edited syllables (for now can just return edited syllables with original indices and everything else gets figured out) --> maybe this reruns syllabic analysis as a sanity check and to make this dev easier lol
                    
                    // Other TODO: server side for receiving syllable override updates (handles single and double dynamically via SyllableOverride class)
                    
                    // get parent word and syllables (parent word can get from raw syllable index - maybe happens server side we'll see)
                }
            }
        } else if (tappingMode == .Tapping) {
            // Key codes: https://stackoverflow.com/questions/28012566/swift-osx-key-event
            if (event.keyCode == 49) { // space bar
                // call wrapper function for handling timing / beat generation
                beatRecord() // TODO: make sure this is consistent
            }
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
        
        // TODO: this should likely be done per bar with the first beat representing the start of the bar (not necessarily the first syllable... maybe a different key is start of the bar unless we just hit space) -- this will be a little slower and clunkier for now but we can figure out better ways as we go
        
        // print out results here and represent in some sort of beat / meter time
        // how do we handle long presses? is everything a quarter note?
        // we should look at press duration as well as offset yeah... test in garageband
        
        // TODO: learn about GarageBand use and MIDIs etc. so that you can have a high level spec in your mind about the nuances of this score annotation system -- specifically thinking about what happens after the initial initialization with ensuring you have the right notes and how that propagates with beats etc. -- that's a little specific dontcha think
        
        // NOTE: how can we simplify the problem to start -- quarter notes only... nah definitely need duration in some sense it's like playing the piano yo know
        
        // NOTE: oooooh would be sick if you could plug in a button device and interface with it -- or remember it's a MacOS app we can use any button
        
        // TODO: maybe this button opens up a dialog for how you want to tap (can use the button itself -- you'll have to on an iPad -- or select another device / tapping mode / key to pull from)
        
        // TODO: this means we'll need to build an abstract interface through which tapping actually gets recorded and each mode (button, key, drum device etc.) just has to report whatever the interface requires (namely duration and time / offset, pitch likely ok for now can look at transient / frequency analysis later)... god i love this shit hahaha
        
        // handle different cases of beat button being tapped
        
        // in general, just incrementing the syllable representation
        
        // let's start with one that we know the syllable representation is good
        
        // open question: how do we handle a syllable representation that's changed post-facto
    }
    
    /*
     TODO: Create new song yessir and tap it --> upload to server for analysis / saving interaction
     TODO: Load song from server (have a slew of songs to download)
     
     Backend TODO: Finish different representations (raw song with endlines, syllabic rhythm proto -- could just be raw timings in case syllables are incorrect but let's assume they're correct yeah -- should be simple to resort if they're incorrectly aligned as long as you can extract original raw timings, + version control and you're golden)
     
     Important TODO: Use git proper (with subprocess calls to a folder which has the name / id of the song as a repo) to store version control of a song with simple diffs (q: do we need git, there may be an easier way)
     
     Goal: Our boy Ye would love this shit -- especially if you could get his damn Stem shits to work hahah -- wonder if it's tuned for this songs (https://www.stemplayer.com/) it's *just* a DSP problem lol
     */
}

