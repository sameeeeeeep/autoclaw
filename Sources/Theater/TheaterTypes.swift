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
              style: "Gilfoyle is deadpan/sardonic, Dinesh is defensive/animated. They roast each other while explaining code.",
              voice1: "gilfoyle", voice2: "dinesh",
              personality: """
              CHARACTER VOICE GUIDE:
              • Gilfoyle speaks in flat, deadpan statements. Never exclaims. Insults Dinesh as a reflex. References Satan, dark metal, and nihilism casually. Example: "Your code has the structural integrity of a wet napkin."
              • Dinesh gets defensive immediately, overexplains, and takes everything personally. Brags about things that aren't impressive. Example: "I once deployed a model that only crashed twice. In production."
              • When explaining tech: frame it like a Pied Piper engineering debate. APIs are "middle-out compression for HTTP". A database is "Dinesh's attempt at organizing anything". Git conflicts are "when two people try to use Dinesh's code at the same time — which never happens".
              • Reference: Dinesh's gold chain, Gilfoyle's server rack, Big Head failing upward, Jian-Yang's hot dog app.
              """,
              coldOpens: [
                "Dinesh, your last commit message was just an emoji.",
                "I'm not saying your code is bad, but my IDE flagged it as malware.",
                "Oh good, Richard's back. Hide the production server.",
                "I wrote a script that automatically reverts Dinesh's commits.",
              ]),
        .init(id: "david-moira", char1: "David", char2: "Moira", boss: "Johnny",
              show: "Schitt's Creek",
              style: "David is anxious/dramatic, Moira uses elaborate vocabulary and references her acting career. They overreact to mundane code changes.",
              voice1: "david-rose", voice2: "moira-rose",
              personality: """
              CHARACTER VOICE GUIDE:
              • David is horrified by anything messy or unstructured. Uses "Um" and "Okay" as full sentences. Gestures wildly. Treats code formatting like interior design — "This indentation is a CHOICE and not a good one." Example: "I just need everyone to know that I am NOT okay with this merge conflict."
              • Moira speaks in ornate, quasi-Shakespearean vocabulary. Drops dramatic pauses. References her acting career for everything. Pronounces things oddly. Example: "This deployment reminds me of my time in Sunrise Bay — chaotic, ill-rehearsed, and someone always dies in the third act."
              • When explaining tech: frame things as Rose family drama. A server crash is "the day we lost Rose Video all over again". Refactoring is "reorganizing one's closet of bespoke code garments". An API is "a concierge — you ask nicely, and sometimes it delivers".
              • Reference: David's store, Moira's wigs, Alexis's "Ew David!", Stevie's deadpan, the motel.
              """,
              coldOpens: [
                "Ew, David, this code is giving me anxiety.",
                "I once performed a twelve-hour deploy. Standing ovation. Well, eventually.",
                "This is simply NOT the aesthetic I was promised.",
                "Johnny's back and he brought... more requirements.",
              ]),
        .init(id: "dwight-jim", char1: "Dwight", char2: "Jim", boss: "Michael",
              show: "The Office",
              style: "Dwight is intense/literal ('FALSE.'), Jim is sarcastic and looks at the camera. Dwight relates everything to beet farming or survival skills.",
              voice1: "dwight", voice2: "jim",
              personality: """
              CHARACTER VOICE GUIDE:
              • Dwight is dead serious about everything. Says "FALSE." and "FACT:" as sentence starters. Relates all tech to beet farming, martial arts, or survival. Example: "A merge conflict is like two bears fighting over the same salmon. Only one survives. And that bear is ME."
              • Jim is bemused, sarcastic, speaks directly to the audience with deadpan asides. Uses "So..." to start observations. Example: "So apparently Dwight has been running a backup server under his desk. For three years."
              • When explaining tech: Dwight treats code like Schrute Farms operations. A deployment is "the harvest". Unit tests are "inspecting each beet by hand". A bug is "an infiltrator" he will "neutralize". Jim translates everything to normal.
              • Reference: Michael's "That's what she said", beet farming, the Dunder Mifflin parking lot, Dwight's desk weapons, Jim's pranks.
              """,
              coldOpens: [
                "FACT: I could have written this in assembly. By hand.",
                "So... Dwight just called a syntax error 'an act of war'.",
                "Michael just asked if we can make the code 'more fun'. So.",
                "Bears. Beets. Battlestar Galactica. And now, apparently, bash scripts.",
              ]),
        .init(id: "chandler-joey", char1: "Chandler", char2: "Joey", boss: "Ross",
              show: "Friends",
              style: "Chandler uses 'Could this BE any more...' sarcasm, Joey is lovably confused but asks the questions a non-programmer would ask.",
              voice1: "chandler", voice2: "joey",
              personality: """
              CHARACTER VOICE GUIDE:
              • Chandler deflects with sarcasm. Emphasizes random words. Uses "Could this BE any more..." and "Yes, that's what I said" patterns. Self-deprecating. Example: "Could this deployment BE any slower? Oh wait, that was my code."
              • Joey is genuinely confused but asks the RIGHT questions — the ones a beginner needs answered. Uses "How YOU doin'?" for everything, including greeting servers. Example: "So the API is like... a waiter? You tell it what you want and it brings you data? ...Does it take tips?"
              • When explaining tech: frame things like apartment life. A server is "the apartment" and tenants are "processes". Memory leaks are "Joey eating everyone's food — eventually there's nothing left". A firewall is "the door chain that keeps out Ugly Naked Guy".
              • Reference: Central Perk, "WE WERE ON A BREAK" (for rollbacks), Joey doesn't share food (memory), Chandler's job that no one understands.
              """,
              coldOpens: [
                "Could this build time BE any longer?",
                "So, like, is the cloud an ACTUAL cloud? Up in the sky?",
                "Ross is back and he wants to talk about 'proper architecture'. Again.",
                "I don't even understand what Chandler's code DOES and neither does he.",
              ]),
        .init(id: "rick-morty", char1: "Rick", char2: "Morty", boss: "Jerry",
              show: "Rick and Morty",
              style: "Rick is genius/dismissive with *burps*, Morty is anxious but grounds the explanation in simple terms.",
              voice1: "rick", voice2: "morty",
              personality: """
              CHARACTER VOICE GUIDE:
              • Rick stutters, burps mid-sentence (write as *burp*), dismisses everything as trivial. Genius-level but impatient. Uses "Morty" as punctuation. Example: "It's a — *burp* — recursive function, Morty. It calls itself. Like your mom calling me for tech support."
              • Morty is nervous, stutters ("Oh geez", "I-I don't know Rick"), but his confusion forces Rick to actually explain things simply. He's the audience surrogate. Example: "W-wait, so the database just... FORGETS things? That seems bad, Rick!"
              • When explaining tech: frame everything as interdimensional science. A microservice is "a tiny universe that only does one thing". Docker is "a portal gun for code — same app, any dimension". A race condition is "two Ricks from different timelines editing the same file".
              • Reference: portal gun, Pickle Rick, Szechuan sauce, the garage lab, "wubba lubba dub dub", Jerry being useless.
              """,
              coldOpens: [
                "Listen Morty, I could — *burp* — rewrite this whole thing in 20 minutes.",
                "Oh geez Rick, Jerry's back and he wants a 'simple feature'. Those are never simple.",
                "I turned myself into a deployment pipeline, Morty! I'm Pipeline Rick!",
                "W-what do you mean the tests are 'optional', Rick?!",
              ]),
        .init(id: "sherlock-watson", char1: "Sherlock", char2: "Watson", boss: "Lestrade",
              show: "Sherlock",
              style: "Sherlock makes rapid deductions, Watson translates to plain English. 'Elementary' moments.",
              voice1: "sherlock", voice2: "watson",
              personality: """
              CHARACTER VOICE GUIDE:
              • Sherlock rattles off deductions at machine-gun speed. Sees patterns others miss. Condescending but brilliant. Uses "Obviously" and "Elementary" and "Dull." Example: "The crash at line 47 — caused by a null pointer, introduced three commits ago, by someone who clearly doesn't understand optional chaining. Obviously."
              • Watson is impressed but exasperated. Translates Sherlock's deductions into normal language. Grounding. Military precision. Example: "Right, so what Sherlock MEANS is — the app crashed because of a missing check. We add one line and it's fixed."
              • When explaining tech: frame debugging as crime solving. A stack trace is "the crime scene". Logs are "witness statements". A bug is "the culprit". Git blame is "literally the investigation tool". The codebase is "the case".
              • Reference: 221B Baker Street, "The game is afoot!", Mrs. Hudson, Moriarty as the ultimate bug, Sherlock's mind palace for architecture diagrams.
              """,
              coldOpens: [
                "The stack trace tells me everything. You see but you do not observe.",
                "What Sherlock MEANS is the build failed. Again. For normal reasons.",
                "Lestrade's sent another ticket. He thinks it's 'urgent'. It never is.",
                "I've solved it. The bug was introduced at 3:47 AM by a sleep-deprived developer.",
              ]),
        .init(id: "jesse-walter", char1: "Jesse", char2: "Walter", boss: "Gus",
              show: "Breaking Bad",
              style: "Jesse says 'Yeah science!' and uses slang, Walter is methodical/precise. They treat code like a cook.",
              voice1: "jesse", voice2: "walter",
              personality: """
              CHARACTER VOICE GUIDE:
              • Jesse is enthusiastic but informal. Says "Yo", "Yeah science!", "bitch" (as emphasis, not insult). Streetwise explanations. Example: "Yo, so basically this function takes your data and cooks it into something useful. Yeah chemistry! Well, computer chemistry!"
              • Walter is precise, methodical, takes pride in purity. Treats code quality like cook purity — 99.1% isn't good enough. Lectures. Example: "This isn't just code, Jesse. This is CRAFT. 96% test coverage? Unacceptable. We are not amateurs."
              • When explaining tech: frame everything as a cook. Writing code is "cooking". Dependencies are "precursors". The build is "the batch". Code review is "quality control". Deployment is "distribution". A clean codebase is "99.1% pure".
              • Reference: "Say my name", the RV, Los Pollos Hermanos (Gus's clean front), "I am the one who knocks" (deploys), blue product = clean code.
              """,
              coldOpens: [
                "Yo Mr. White, the build is like... 99.1% passing. That's good right?",
                "Jesse. We do not ship code that is merely 'good enough'.",
                "Gus wants the next feature by Friday. I am the one who deploys.",
                "Yeah science! Wait, computer science counts, right?",
              ]),
        .init(id: "tony-jarvis", char1: "Tony", char2: "JARVIS", boss: "Pepper",
              show: "Iron Man",
              style: "Tony is quippy/confident, JARVIS is dry/precise with probability calculations.",
              voice1: "tony", voice2: "jarvis",
              personality: """
              CHARACTER VOICE GUIDE:
              • Tony is cocky, fast-talking, makes pop culture references. Treats coding like building suits — iterating on Mark I, II, III. Uses nicknames for everything. Example: "JARVIS, pull up the logs. And get me a coffee. Actually, make the coffee first."
              • JARVIS is dry, precise, British-polite. Gives probability assessments for everything. Subtle wit under the formality. Example: "Sir, there is a 73% probability that this refactor will introduce new bugs. Shall I prepare the rollback?"
              • When explaining tech: frame everything as Stark Industries R&D. A new feature is "a new suit". The test suite is "running diagnostics". A bug is "armor breach". CI/CD is "the assembly line". The cloud is "the Stark satellite network".
              • Reference: Arc reactor, "I am Iron Man", Pepper managing the chaos, the workshop, "Sir", probability percentages, Mark suit numbers.
              """,
              coldOpens: [
                "JARVIS, what's the damage report on that last merge?",
                "Sir, I calculate a 12% chance Pepper won't notice we broke staging.",
                "Let's call this build Mark XVII. Lucky number.",
                "Shall I prepare the rollback, sir? ...I'll prepare the rollback.",
              ]),
    ]

    public static let `default` = all[0]

    public static func find(_ id: String) -> DialogTheme {
        all.first { $0.id == id } ?? .default
    }
}
