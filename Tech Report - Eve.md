# CH4-AI-Reminder

## 1. Present Your Team
- Amanda
- Caca
- Dani
- Keiko
- Nanda

## 2. Starting Assumption
Going into this project, our primary assumption was that CoreML would be the foundational framework of our entire development stack. We believed that no matter what kind of AI application we designed, CoreML was universally required under the hood to act as the primary pipeline connecting any AI models to native Swift code.

## 3. The Exploration Log

### What we browsed, and what surprised us:
- CreateML, we notice that we can create and train an ML model with zero code in XCode.
- Apple Intelligence uses powerful foundation models and connects them to the Apple ecosystem so they can understand our personal context.
- As a developer, if we want to use the foundation models that are already built into Apple Intelligence, we don't have to deal with CoreML ourself.
- The only time we would still need CoreML is if we want to bring our own completely custom or proprietary model (like a specific model we trained ourself on our own servers) and force it to run locally on the user's iPhone.
- If we are connecting our app to a third-party model running on a remote server (for example, using the OpenAI API, Anthropic API, or our own AWS/Hugging Face cloud server), we don't need CoreML. We can just use standard web networking code (URLSession in Swift) to send text to their server and get a response back.
- Importing Foundation in Swift is completely different from 'Foundation Models' in AI. Foundation Models are large-scale machine learning models trained on broad data to perform varied AI tasks. In contrast, Swift's Foundation is a core software framework that provides essential base capabilities, like data storage, file management, networking, and date formatting, for Apple and Swift development.
- The difference between action classification and activity classification is action for body movements so it needs video as an input meanwhile activity is for motion sensor.
- AVFoundation is an Apple framework used to work with audiovisual media like if we want to play audio files, records video from the camera, inspect media metadata, compresses video files, and handles speech synthesis (text-to-speech).
- AppIntent used to connects app's features to system-wide automation tools like the Shortcuts app, Siri, and Apple Intelligence. It allows us to expose specific actions from our app to the rest of the OS. For example, if we have a journaling app, we can create an AppIntent called "Create New Entry." Apple Intelligence or Siri can then trigger that action even when our app is closed.
- CoreLocation is the GPS and geography engine.
- UserNotification is the push notification manager.
- We can use Playgrounds to test the performa of Foundation Models.

Moving forward, we decided to make the Foundation Models framework our primary area of exploration. It offers a massive amount of untapped potential, and we are eager to discover how its latest updates perform inside the iOS 27 Beta.

### What we actually built or tested in code (not just read about):
- Lakon, a fully offline interactive story game.
- AI Itinerary planner, a localized travel application that generates custom trip plans using native Foundation Models.
- An image-to-text application built using the Google Gemini API for automated captioning.

### What we experienced with on-device Foundation Models (Apple Intelligence):
- Finding specific video clips or photos just by describing a mood, view, or action.
- Understanding personal schedules to surface context-aware, highly relevant reminders.
- Processing spoken requests fluently via an enhanced, conversational Siri.
- Snapping a picture of ingredients to instantly get a step-by-step recipe.
- Recognizing and interacting with text or pages within a physical book.
- Instantly stitching together photos and videos into a short "Memory Movie" based on a prompt.
- Creating custom, mood-based music playlists tailored to a specific ambiance or setting.

### What we discovered that we didn't expect:
- Media search is precise but subjective. It’s amazing at pinpointing specific durations and actions inside a video. However, abstract vibes like "moody" or "cinematic" are hit-or-miss and often require rewording the prompt due to varying human definitions of those moods.
- The models excel at analyzing personal schedules to deliver highly relevant and intelligent daily activity suggestions.
- While Siri is significantly improved, it still struggles with background noise isolation and precise word recognition. It sometimes takes a few tries to get Siri to understand and perform better our exact request.
- The visual recognition is spot-on for identifying ingredients, but the recipe generation can lose track of quantity (e.g., calling for two eggs when the photo only had one).
- We were impressed that it can pinpoint the exact title of a book based on a single photo of one random page.
- Making short videos from text prompts works, but expect a noticeable rendering lag if you are feeding it with a large amount of media or complex prompts.
- Apple Intelligence doesn't synthesize original music. In testing ambient audio prompts, it first pulled existing matching playlists from Apple Music, and on a subsequent attempt, simply fell back to Apple’s built-in, static background sounds.
- We can define both a user-facing `prompt` and a system-level `instruction` in code. System instructions allow us to anchor the foundation model to specific rules, roles, or constraints, ensuring relevant outputs even when user input varies wildly.
- We utilized a `switch` statement to robustly handle different model availability states (e.g., checking if the model is fully downloaded, restricted, or currently unavailable on the device).
- To enforce a neat, predictable data structure from the model, we annotated our Swift models with `@Generable`. We then used the `@Guide` macro on individual properties to give the model precise, inline context about what each data field represents.
- We discovered we can dramatically improve model accuracy using standard Swift syntax. We can inject native logic like `if` statements and loops for structured engineering, or pass mock object instances directly into the prompt to act as few-shot examples for the model to mirror.
- To prevent the UI from freezing while waiting for a full response, we can implement the streaming API using `streamResponse`. By tagging properties with `PartiallyGenerated`, the UI can display the output word-by-word as it streams, creating a much more engaging user experience.
- We can expand the model's reach by implementing Tools. These are standard Swift functions exposed to the foundation model, allowing it to autonomously fetch real-time external data or execute local app actions when needed.
- We can implement two critical techniques to minimize response lag:
  * Calling `prewarmModel()` inside a view task modifier to load the model into memory before the user requests it.
  * Setting `includeSchemaInPrompt: false` inside the `session.streamResponse` call to reduce token overhead and speed up processing times.

## 4. What We Tried and Dropped
- We originally designed a conceptual AI video editor capable of identifying specific scenes, emotions, or highlight-worthy moments to automatically curate long-form footage into short, meaningful clips using a stack of **Foundation Models, AVFoundation, and AppIntents**. We pivoted away from this concept because native Apple Intelligence features (such as Memory Movies and advanced Photos search) already handle this behavior. Furthermore, testing revealed that foundation models still struggle with highly subjective emotional prompts (like "moody" or "cinematic") due to the variance in human interpretation.
- We explored an automated journaling application that could process a user's prompt, pull matching media assets, and generate descriptive text into a digital scrapbook layout. We shelved this idea for two reasons: a competitive audit showed an over-saturation of AI journaling concepts since our initial stage, and the core value proposition of a scrapbook relies heavily on visual layout and scrapbook design, whereas this challenge strictly tasked us with exploring deep technical implementation of frameworks.

## 5. Real Limitations Hit
We attempted to use the Foundation Models framework combined with `AVFoundation` to build an AI assistant video editor that could extract highlights based on emotional moods (like "sad," "cinematic," or "moody"). While the documentation states that the model excels at isolating actions and precise timestamps, it repeatedly struggled with these abstract requests. Because human definitions of a "vibe" vary, the model failed to return consistent, reliable results for subjective keywords. We dropped the dedicated app concept when we realized native Apple Intelligence features (like Memory Movies and advance Photos search) already handle this behavior.

Besides that, we also notice that Foundation models can't solve a complex reasoning, long-context tasks, general world knowledge, code generation, and math. To maximize and isolate the true potential of Apple's Foundation Models framework, we made a deliberate architectural decision not to introduce or implement any external third-party models or cloud AI runtimes.

Once we moved from research into an actual working build, several new realities surfaced that we hadn't fully anticipated during the exploration phase.
- The model still halucinates. Even with a fully native pipeline, the Foundation Model occasionally hallucinates, most visibly by producing a reminder that doesn't match the context it was given (surfacing the wrong action). When we debugged these cases, we traced the likely causes to three layers:
  * Prompt quality (developer side): vague, under-specified, or poorly structured prompts leave too much room for the model to guess.
  * Context data available to the model: when the insight data we feed it is thin or ambiguous, the model fills the gaps with fabrications.
  * Quality of the processed data: noisy, inconsistent, or poorly formatted input data degrades the reliability of the output.
- Language support is narrower than expected. The Foundation Model does not reliably process every language. For non-English input, we effectively need a `Natural Language` framework as a translation step to convert the text into English before the model can reason over it, because several languages simply don't work well (or at all) with the on-device model yet.
- The model has no long-term memory. The Foundation Model can't continuously remember or persist user data on its own. It is effectively stateless between calls.

## 6. The Revised Decision

### Final decision:
We are building an AI-powered Adaptive Reminder Assistant that leverages a native framework pipeline consisting of **Foundation Models + Natural Language + EventKit + CoreLocation + UserNotifications + SwiftData.** The application is designed to passively learn user schedules, routines, and physical habits over time, delivering hyper-contextual, non-intrusive reminders that dynamically adapt based on real-world environment variables, behavioral cues, and lightweight, active user feedback loops.

### What changed since Section 1, and why:
Our core strategy completely pivoted to embrace an exclusive native architecture. While our initial ideations relied on heavy, design-dependent applications or complex multi-model pipelines, we discovered that the true potential of Apple's Foundation Models framework is best unlocked when it operates completely on its own, natively on-device. We explicitly dropped alternative ideas (like the AI video editor and automated scrapbook) because they either duplicated built-in Apple features or over-indexed on UI layout over deep technical experimentation. By focusing on a smart context assistant, we harness the baseline strengths of Apple Intelligence: zero-latency local execution, complete on-device privacy, and direct integration with the operating system.

During development, we decided to incorporate the **Natural Language** framework as an additional core framework. We found that the on-device Foundation Model currently has limited support for some non-English languages. By using the Natural Language framework to detect and translate non-English user input into English before passing it to the Foundation Model, we ensure that the model can reason over the input more accurately and consistently across different languages.

We also discovered an important limitation of the on-device Foundation Model: it is stateless, meaning it cannot continuously remember or persist user information across interactions. Rather than relying on the model to retain the user's history, we store the assistant's learned understanding as AI Insights in **SwiftData**. The Foundation Model is invoked only when needed, and each time it runs, it reasons over the persisted insights and current context instead of relying on memory from previous sessions. In other words, the Foundation Model provides the reasoning, while SwiftData serves as the long-term memory.

## App Track Addendum
### About the frameworks
Our use case absolutely mandates the strict collaboration of all these frameworks. The application could not function with the main Foundation Models framework alone. While the Foundation Model acts as the core "brain" for reasoning and personalization, it is completely isolated from the device's hardware, operating system data, and user interface. It lacks the native capability to fetch live data, track physical locations, or trigger system alerts on its own.

The secondary frameworks serve as the essential eyes, ears, and hands for the AI model:
- EventKit: This framework is required to sync directly with Apple’s native Calendar and Reminders applications. It extracts the historical and upcoming timeline data that the Foundation Model analyzes to map, predict, and understand the user's initial routine patterns.
- CoreLocation: Acts as the sensory trigger, feeding real-time geographical coordinates to the app so the model can determine when a user has arrived at a relevant destination.
- UserNotifications: Because the core utility of an adaptive assistant relies entirely on timely engagement, this framework is critical. UserNotifications is the primary channel used to deliver the final adaptive reminders and request lightweight clarification prompts when the user is on the move.

### About accessibility and localization
We designed EVE around the concept of micro-habits—small but important everyday actions that are easy to forget, such as bringing a water bottle, taking medication, charging a device, or picking up groceries before leaving work. These tasks often rely on prospective memory and context, making them particularly challenging for people with ADHD or executive dysfunction, who may struggle with initiating tasks, switching attention, or remembering intentions at the right moment. Rather than using fixed, repetitive reminders, EVE delivers adaptive reminders based on the user's current context, helping reduce the cognitive effort required to remember these small but essential routines.

Because users with executive dysfunction can also experience cognitive overload when interacting with digital products, we intentionally designed EVE to minimize the effort required to use the app itself. Our design principles are:
- Dark interface as an accessibility feature, giving users the option to reduce visual stimulation and improve comfort in low-light environments.
- We minimize on-screen clutter and surface a single, clear primary action per screen, cutting the decision fatigue and task paralysis that often stall ADHD users.
- Feedback loops are lightweight and tap-based rather than typing-heavy, so responding to the app never feels like a chore.

We do not support entirely disengaged users who use neither Apple's native Calendar/Reminders apps nor participate in our questionnaires. Without passive EventKit telemetry or active feedback, the Foundation Model hits a "blank slate" constraint and cannot personalize routines.

The application will be natively developed and fully supported in English. As a direct consequence of the language limitation above, we reversed our earlier plan to localize into Bahasa Indonesia. The Foundation Model doesn't yet work reliably in Indonesian, so shipping an Indonesian experience would mean shipping a broken AI core. For now the app stays English-only, and Indonesian localization is deferred until on-device language support matures.

### About privacy
Because we use Apple’s native Foundation Models framework, all data processing happens strictly on-device. We require three data channels:
- Calendar & Reminder (`EventKit`): To analyze historical schedules and map the user's baseline routine.
- GPS (`CoreLocation`): To detect real-world arrivals and departures for location-based prompts.
- `UserNotifications`: To deliver adaptive reminders and collect lightweight questionnaire feedback.

The app uses a graceful degradation strategy to keep functioning under system constraints:
- If `EventKit` is Denied: The model loses passive timeline data and switches to an active-learning mode, building the user’s routine profile solely through notification questions.
- If `CoreLocation` is Denied: Geographic triggers are disabled. The model automatically recalculates schedules using purely time-based constraints (e.g., "30 minutes after waking up").
- If `UserNotifications` is Denied: All lock-screen engagement is blocked. The app falls back to an in-app dashboard experience, requiring the user to open the app manually to view their queued reminders and feedback questions.
- If All Permissions Are Denied: The model hits a hard constraint. With zero telemetry or delivery channels, the app halts and displays an onboarding screen explaining that the AI needs at least one data source to begin tracking routines.
