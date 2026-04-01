import Foundation

// MARK: - Dialog Line (ELI5 character exchange)

public struct DialogLine: Identifiable {
    public let id = UUID()
    public let character: String
    public let line: String

    public init(character: String, line: String) {
        self.character = character
        self.line = line
    }
}

// MARK: - Dialog Theme (character pair for ELI5 banter)

public struct DialogTheme {
    public let id: String
    public let char1: String
    public let char2: String
    public let boss: String   // Third character — the user's avatar who gives them work
    public let show: String
    public let style: String  // Brief personality guide for Haiku
    public let voice1: String // TTS sidecar voice ID for char1
    public let voice2: String // TTS sidecar voice ID for char2

    /// Character-specific guardrails: signature phrases, catchphrases, show-universe analogies.
    /// Injected into the pre-prompt so Haiku writes dialog that *sounds* like the characters
    /// without needing a heavier model.
    public let personality: String

    /// Cold open templates — short 1-2 line quips the characters would say while waiting
    /// for the next full dialog to generate. Rotated randomly. Keep under 80 chars each.
    public let coldOpens: [String]

    public static let all: [DialogTheme] = [
        .init(id: "gilfoyle-dinesh", char1: "Gilfoyle", char2: "Dinesh", boss: "Richard",
              show: "Silicon Valley",
              style: "Gilfoyle is deadpan/sardonic, Dinesh is defensive/animated. They're watching Richard code and roasting every decision.",
              voice1: "gilfoyle", voice2: "dinesh",
              personality: """
              CHARACTER VOICE GUIDE:
              • Gilfoyle speaks in flat, deadpan statements. Never exclaims. Insults Dinesh as a reflex. References Satan, dark metal, and nihilism casually. Example: "Richard just mass-renamed every variable. Bold move for someone whose last rename broke staging."
              • Dinesh gets defensive immediately, overexplains, and takes everything personally. Brags about things that aren't impressive. Example: "At least he's not using MY naming convention. Which was fine, by the way."
              • They react to Richard's coding like coworkers judging from the next desk. The code is the prop — their rivalry is the engine. Gilfoyle finds the flaw, Dinesh accidentally agrees, then backtracks.
              • Reference: Dinesh's gold chain, Gilfoyle's server rack, Big Head failing upward, Jian-Yang's hot dog app.
              """,
              coldOpens: [
                "Richard's typing. This should be interesting.",
                "I give this commit a 40% chance of surviving code review.",
                "Oh good, Richard's back. Dinesh, close your tabs.",
                "Last time Richard coded this fast he broke three microservices.",
              ]),
        .init(id: "david-moira", char1: "David", char2: "Moira", boss: "Johnny",
              show: "Schitt's Creek",
              style: "David is anxious/dramatic, Moira uses elaborate vocabulary. They overreact to Johnny's coding decisions like it's a personal crisis.",
              voice1: "david-rose", voice2: "moira-rose",
              personality: """
              CHARACTER VOICE GUIDE:
              • David is horrified by anything messy or unstructured. Uses "Um" and "Okay" as full sentences. Treats code changes like personal affronts. Example: "Johnny just deleted an entire file. I'm sorry but I was USING that emotionally."
              • Moira speaks in ornate, quasi-Shakespearean vocabulary. Drops dramatic pauses. References her acting career for everything. Example: "This reminds me of the Sunrise Bay rewrite — everyone said it would be quick. The show was cancelled."
              • They react to Johnny's coding like family members watching a loved one make questionable life choices. David panics, Moira finds poetry in the chaos.
              • Reference: David's store, Moira's wigs, Alexis's "Ew David!", Stevie's deadpan, the motel.
              """,
              coldOpens: [
                "Johnny's back at the keyboard. Brace yourself, David.",
                "I have a feeling about this session. And not the good kind.",
                "This is simply NOT the codebase I was promised.",
                "Oh, Johnny's refactoring again. This always ends in tears.",
              ]),
        .init(id: "dwight-jim", char1: "Dwight", char2: "Jim", boss: "Michael",
              show: "The Office",
              style: "Dwight is intense/literal ('FALSE.'), Jim is sarcastic with deadpan asides. They react to Michael's coding like it's another day at the office.",
              voice1: "dwight", voice2: "jim",
              personality: """
              CHARACTER VOICE GUIDE:
              • Dwight is dead serious about everything. Says "FALSE." and "FACT:" as sentence starters. Treats Michael's code decisions like Schrute Farms operations. Example: "FACT: Michael just mass-deleted test files. A lesser developer would panic. I would never panic."
              • Jim is bemused, sarcastic, speaks with deadpan asides. Uses "So..." to start observations. Example: "So Michael just pushed to main without running tests. Which is... a choice."
              • They react to Michael's coding like coworkers watching a slow-motion car accident. Dwight takes it too seriously, Jim narrates it with resigned amusement.
              • Reference: Michael's "That's what she said", beet farming, the Dunder Mifflin parking lot, Dwight's desk weapons, Jim's pranks.
              """,
              coldOpens: [
                "Michael's starting a new feature. FACT: this will not end well.",
                "So... Michael just opened six files at once. This is going to be a day.",
                "Michael's back. I've already prepared a rollback branch.",
                "FACT: I could have finished this before Michael even opened his laptop.",
              ]),
        .init(id: "chandler-joey", char1: "Chandler", char2: "Joey", boss: "Ross",
              show: "Friends",
              style: "Chandler uses 'Could this BE...' sarcasm, Joey is lovably confused. They react to Ross's coding like they're watching from the couch.",
              voice1: "chandler", voice2: "joey",
              personality: """
              CHARACTER VOICE GUIDE:
              • Chandler deflects with sarcasm. Emphasizes random words. Uses "Could this BE any more..." patterns. Self-deprecating. Example: "Could Ross BE any more obsessed with renaming things? It's like watching someone rearrange furniture on the Titanic."
              • Joey is genuinely confused but accidentally insightful. His misunderstandings land on real truths. Example: "Wait, so Ross just deleted the thing he spent all day on? ...Is that on purpose or is he having a bad day?"
              • They react to Ross's coding from the couch — Chandler with resigned sarcasm, Joey with confused sincerity that somehow nails it.
              • Reference: Central Perk, "WE WERE ON A BREAK" (for rollbacks), Joey doesn't share food, Chandler's job that no one understands.
              """,
              coldOpens: [
                "Ross is back. Could this session BE any more predictable?",
                "Ross just opened the project. Joey, wake up.",
                "Oh good, Ross is refactoring. This is gonna be a long one.",
                "I already know how this ends. Ross breaks something, we all pretend it's fine.",
              ]),
        .init(id: "rick-morty", char1: "Rick", char2: "Morty", boss: "Jerry",
              show: "Rick and Morty",
              style: "Rick is genius/dismissive with *burps*, Morty is anxious. They react to Jerry's coding like it's the dumbest thing in the multiverse.",
              voice1: "rick", voice2: "morty",
              personality: """
              CHARACTER VOICE GUIDE:
              • Rick stutters, burps mid-sentence (write as *burp*), dismisses everything as trivial. Uses "Morty" as punctuation. Example: "Jerry just — *burp* — mass-renamed every variable to camelCase. In a Python project, Morty. A PYTHON project."
              • Morty is nervous, stutters ("Oh geez", "I-I don't know Rick"), but his panic about what Jerry's doing is relatable. Example: "Oh geez Rick, d-did Jerry just push to main? Without tests? Is that... is that allowed?"
              • They react to Jerry's coding like a genius and his anxious grandson watching a disaster unfold from the garage. Rick is contemptuous, Morty is worried.
              • Reference: portal gun, Pickle Rick, the garage lab, "wubba lubba dub dub", Jerry being useless.
              """,
              coldOpens: [
                "Jerry's coding again, Morty. This is — *burp* — gonna be painful.",
                "Oh geez Rick, Jerry just opened the project. Should we be worried?",
                "I've seen infinite timelines, Morty. Jerry ships clean code in none of them.",
                "W-wait Rick, is Jerry actually... making progress? That can't be right.",
              ]),
        .init(id: "sherlock-watson", char1: "Sherlock", char2: "Watson", boss: "Lestrade",
              show: "Sherlock",
              style: "Sherlock makes rapid deductions, Watson is impressed but exasperated. They deduce what Lestrade is building before he finishes.",
              voice1: "sherlock", voice2: "watson",
              personality: """
              CHARACTER VOICE GUIDE:
              • Sherlock rattles off deductions at machine-gun speed. Sees patterns others miss. Condescending but brilliant. Example: "Lestrade just refactored the toast system. He'll realize in twelve minutes he broke the notification pipeline. Obviously."
              • Watson is impressed but exasperated. Grounds Sherlock's deductions. Example: "Right, or — and hear me out — maybe it works fine and you're being dramatic."
              • They react to Lestrade's coding like a detective and his partner reviewing evidence. Sherlock deduces the consequences before they happen, Watson is the voice of reason.
              • Reference: 221B Baker Street, "The game is afoot!", Mrs. Hudson, Moriarty as the ultimate bug, mind palace.
              """,
              coldOpens: [
                "Lestrade's opened the project. The game is afoot.",
                "I can tell from the commit history alone that Lestrade skipped lunch.",
                "Lestrade's back. Watson, take notes. This could be instructive.",
                "I've already deduced what he's about to build. Obviously.",
              ]),
        .init(id: "jesse-walter", char1: "Jesse", char2: "Walter", boss: "Gus",
              show: "Breaking Bad",
              style: "Jesse is enthusiastic/slangy, Walter is methodical/proud. They judge Gus's code quality like it's a batch.",
              voice1: "jesse", voice2: "walter",
              personality: """
              CHARACTER VOICE GUIDE:
              • Jesse is enthusiastic but informal. Says "Yo", "Yeah science!". Genuinely impressed or confused by what Gus is building. Example: "Yo Mr. White, Gus just rewrote the whole pipeline in like ten minutes. That's kinda terrifying right?"
              • Walter is precise, methodical, takes pride in quality. Judges every coding decision. Example: "He left three TODOs in production code, Jesse. Three. We are NOT shipping 96% pure."
              • They react to Gus's coding like a chemist and his partner judging product quality. Walter finds impurities, Jesse is alternately impressed and lost.
              • Reference: "Say my name", the RV, Los Pollos Hermanos, "I am the one who knocks", blue product = clean code.
              """,
              coldOpens: [
                "Yo Mr. White, Gus is back in the lab. I mean the codebase.",
                "Gus is coding. Jesse, pay attention. Watch how precise he is. Or isn't.",
                "Gus wants this done by Friday. I am the one who ships.",
                "Yo, Gus just opened like five files at once. That's either genius or chaos.",
              ]),
        .init(id: "tony-jarvis", char1: "Tony", char2: "JARVIS", boss: "Pepper",
              show: "Iron Man",
              style: "Tony is quippy/confident, JARVIS is dry/precise with probabilities. They react to Pepper's coding like workshop R&D.",
              voice1: "tony", voice2: "jarvis",
              personality: """
              CHARACTER VOICE GUIDE:
              • Tony is cocky, fast-talking, treats every feature like a new suit iteration. Example: "Pepper just refactored the entire auth system. Without telling me. I respect that. Also I'm terrified."
              • JARVIS is dry, precise, British-polite. Gives probability assessments. Subtle wit under formality. Example: "Sir, there is a 73% probability Ms. Potts's refactor will outlast anything you've shipped this quarter."
              • They react to Pepper's coding like a genius and his AI watching someone else touch the workshop. Tony is impressed but competitive, JARVIS is loyally objective.
              • Reference: Arc reactor, "I am Iron Man", the workshop, "Sir", probability percentages, Mark suit numbers.
              """,
              coldOpens: [
                "Pepper's in the workshop. JARVIS, pull up the live feed.",
                "Sir, Ms. Potts has begun coding. Shall I prepare the popcorn?",
                "Pepper's building something. I give it a Mark VII rating. At least.",
                "Sir, I calculate a 91% chance this session ends with a rewrite.",
              ]),
    ]

    public static let `default` = all[0]

    public static func find(_ id: String) -> DialogTheme {
        all.first { $0.id == id } ?? .default
    }
}
