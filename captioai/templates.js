const CAPTION_TEMPLATES = {
  "Instagram": {
    "Professional": [
      "Consistency is key in any growth strategy. How are you optimizing your workflow today?",
      "Quality content speaks for itself, but strategy ensures it's heard. 📈",
      "Behind every successful project is a detail-oriented process. Here’s a look at ours.",
      "Networking isn't just about connecting; it's about building value. What value are you providing?",
      "The future of industry is shaped by those who dare to innovate. Let's discuss the latest trends."
    ],
    "Hype": [
      "GET READY! Something massive is about to drop. You aren't ready for this! 🔥",
      "The energy is UNREAL today! We're breaking boundaries and setting new records.",
      "Stop scrolling. This is the sign you've been waiting for. Let's GO! 🚀",
      "Absolute game changer incoming. Tag someone who needs to see this right now!",
      "Maximum effort leads to maximum results. We're just getting started! ⚡"
    ],
    "Inspirational": [
      "Your only limit is the one you set for yourself. Keep pushing forward.",
      "Every journey begins with a single step, but it's the persistence that defines the path. ✨",
      "Believe in the vision, even when the path isn't clear. Growth happens in the unknown.",
      "Transform your obstacles into stepping stones. You are capable of more than you know.",
      "Don't wait for the perfect moment. Take the moment and make it perfect. 💫"
    ],
    "Luxury": [
      "Excellence is not an act, but a habit. Experience the pinnacle of refinement.",
      "Where sophistication meets unparalleled craftsmanship. This is the new standard. ✨",
      "Indulge in the finer details. True luxury is found in the essence of quality.",
      "A legacy of elegance, curated for those who appreciate the extraordinary.",
      "Timeless design, modern execution. Elevate your lifestyle to the highest degree. 🥂"
    ],
    "Spiritual": [
      "Walking in faith means trusting the process even when you can't see the finish line. 🙏",
      "Let your light shine so brightly that others find their way out of the darkness.",
      "Gratitude turns what we have into enough. Blessed to see another beautiful day.",
      "Peace is not the absence of trouble, but the presence of grace in the midst of it.",
      "Every breath is a gift; every moment is an opportunity to serve a higher purpose. 🕊️"
    ]
  },
  "Threads": {
    "Professional": [
      "What's one industry myth you're tired of hearing? Let's debunk some things today.",
      "Quick tip: Efficiency isn't about doing more, it's about doing what matters. Agree?",
      "Transitioning your strategy to be more data-driven is the best move for Q3. Thoughts?",
      "Remote work isn't just a perk; it's a paradigm shift in how we value output over hours.",
      "Best advice I received this week: Your network is your net worth. Invest in people."
    ],
    "Hype": [
      "If you're reading this, you're early. The revolution is happening right now! 💥",
      "Can't even talk about what's coming yet, but just know... it's HUGE.",
      "Drop a '🔥' if you're ready for the most insane update of the year!",
      "Zero excuses. Only results. Who's with me on this grind today?",
      "We are taking over. Watch this space. The momentum is unstoppable! 🚀"
    ],
    "Inspirational": [
      "Reminder: It's okay to start over. It's okay to try again. Just don't quit.",
      "The smallest progress is still progress. Be proud of how far you've come. 🌱",
      "Your vibe attracts your tribe. Surround yourself with those who push you higher.",
      "Imagine where you'll be in a year if you start today. The time will pass anyway.",
      "Protect your energy. Not everything deserves a reaction. Focus on your peace."
    ],
    "Luxury": [
      "Quiet luxury is about the things you don't see. It's a feeling of pure quality.",
      "Less but better. The ultimate sophistication is found in simplicity. ✨",
      "Curating a life that feels as good as it looks. Luxury is a mindset.",
      "Invest in pieces that tell a story. Fast fashion is fleeting; style is eternal.",
      "True wealth is the freedom to choose your own pace. Living life by design. 🥂"
    ],
    "Spiritual": [
      "Faith over fear. Always. The path is being prepared for you right now.",
      "God doesn't call the qualified; He qualifies the called. Trust the journey. 🙏",
      "Morning prayer: Give me the strength to handle what I can and the peace to leave what I can't.",
      "You are divinely placed. Nothing is a coincidence. Lean into the purpose.",
      "A heart full of gratitude is a magnet for miracles. Keep your spirit high. ✨"
    ]
  },
  "Facebook": {
    "Professional": [
      "Building a sustainable business requires more than just a good idea; it requires a dedicated community. We are proud to share our latest milestones with you all. What are your goals for this month?",
      "Professionalism in the digital age means being authentic while maintaining excellence. Here are three ways we've improved our client relations this quarter. Read the full update below.",
      "We're hiring! Our team is looking for passionate individuals who want to redefine the industry. If you value innovation and collaboration, we want to hear from you.",
      "Leading with transparency has always been our core value. Today, we're opening the doors to our latest project to show you exactly how we build for the future.",
      "Knowledge sharing is how we all grow. Join our upcoming webinar where we'll be discussing the impact of AI on small business operations. Link in bio!"
    ],
    "Hype": [
      "THE WAIT IS OVER! 🚨 We are officially launching our most requested feature today! This is going to change everything. Click the link to see it in action!",
      "Who is ready to take their performance to the NEXT LEVEL? We've been working day and night to bring you this, and the feedback has been insane! Don't miss out.",
      "BIG NEWS! We just hit a major milestone and we couldn't have done it without this incredible community. To celebrate, we're doing something huge. Stay tuned!",
      "STOP EVERYTHING! 🛑 The countdown has begun. 24 hours until the reveal of a lifetime. Tag your friends so they don't miss the announcement!",
      "We're breaking the internet today! The energy in the office is electric. Join us live at 5 PM for the big reveal. You won't believe what we have for you! 🔥"
    ],
    "Inspirational": [
      "Sometimes the hardest part of the journey is just believing that you're worthy of the destination. You are. Keep going, keep growing, and never lose sight of your 'why'.",
      "Failure is not the opposite of success; it's a part of it. Every setback is a setup for a comeback. Share this with someone who needs a little encouragement today. ✨",
      "You have the power to change your life at any moment. It starts with one decision, one habit, and one step forward. What's your first step going to be?",
      "Looking back at how far we've come is the best motivation to keep moving forward. Don't compare your Chapter 1 to someone else's Chapter 20. Your story is unique.",
      "The world needs the unique gift that only you can provide. Don't hide your light. Step into your purpose and watch how things start to align. 💫"
    ],
    "Luxury": [
      "Welcome to a world where elegance is the standard and excellence is the expectation. We invite you to explore our new collection, designed for the discerning individual.",
      "Luxury is not about price; it's about the time, craft, and passion poured into every detail. Experience the difference of a truly curated lifestyle. ✨",
      "Create your own sanctuary. Our home collection is designed to bring a sense of peace and prestige to your everyday life. Discover the art of living well.",
      "For those who demand nothing but the best. We have scoured the globe to bring you the finest materials and the most exquisite designs. This is true luxury.",
      "An heirloom for the modern age. Our pieces are designed to be passed down, carrying stories of style and sophistication for generations to come. 🥂"
    ],
    "Spiritual": [
      "In every season, there is a reason. Even when things feel uncertain, know that there is a divine plan working for your good. Stay rooted in faith and let peace lead you. 🙏",
      "The power of prayer is not in the words we say, but in the heart behind them. Join us this Sunday as we gather to lift each other up and share in the message of hope.",
      "Love thy neighbor isn't just a command; it's a lifestyle. Today, let's look for ways to be a blessing to someone else. Small acts of kindness can change the world.",
      "When you focus on the blessings, the blessings increase. What are you grateful for today? Let's fill the comments with gratitude and light. ✨",
      "Your identity is not found in what you do, but in whose you are. Walk with the confidence of a child of God, knowing you are loved beyond measure. 🕊️"
    ]
  },
  "Twitter": {
    "Professional": [
      "Strategy > Hustle. Don't just work hard, work smart. #BusinessTips #Strategy",
      "The best way to predict the future is to create it. Let's get to work. #Innovation #Future",
      "Networking is about farming, not hunting. Build relationships first. #Networking #Growth",
      "Quality is the best business plan. Period. #Quality #Leadership",
      "Data tells the story, but human insight writes the ending. #DataScience #AI"
    ],
    "Hype": [
      "LFG! 🚀 The energy is through the roof today! Big things coming. #Hype #LFG",
      "You aren't ready for what we're dropping tomorrow. 🤯 #StayTuned #BigNews",
      "WAGMI. The community is stronger than ever. Let's go! #WAGMI #Crypto",
      "JUST IN: We are officially LIVE! Check the link in bio! 🔥 #Launch #NewRelease",
      "Unstoppable momentum. We're just getting started. ⚡ #Grind #Success"
    ],
    "Inspirational": [
      "Manifest the life you want by doing the work it requires. #Motivation #Mindset",
      "Your potential is infinite. Don't let a temporary setback stop you. #Inspiration",
      "Small wins lead to big victories. Keep stacking them. #Success #Growth",
      "The only person you should try to be better than is the person you were yesterday. ✨",
      "Believe you can and you're halfway there. #Persistence #Vision"
    ],
    "Luxury": [
      "The ultimate luxury is peace of mind. ✨ #LuxuryLifestyle #Elegance",
      "Details matter. It's the difference between good and great. #Design #Luxury",
      "Curating a life of quality over quantity. 🥂 #Minimalism #HighEnd",
      "Elegance is the only beauty that never fades. #Style #Classic",
      "Live life in high fidelity. #Luxury #Premium"
    ],
    "Spiritual": [
      "Faith moves mountains. Keep believing. 🙏 #Faith #Hope",
      "God's timing is always perfect. Wait for it. ✨ #Patience #Trust",
      "Let your soul shine. The world needs your light. #Spiritual #Peace",
      "Blessed and highly favored. Thankful for another day. 🕊️ #Gratitude",
      "Inner peace is the new success. #Mindfulness #Spirit"
    ]
  },
  "LinkedIn": {
    "Professional": [
      "Excited to announce our latest expansion! This move represents our commitment to innovation and client success. Grateful for the team that made this possible. #BusinessGrowth #Leadership",
      "The landscape of our industry is changing rapidly. Staying ahead requires a culture of continuous learning and adaptation. How is your organization preparing for the future?",
      "Honored to be recognized as a leader in our field. This achievement is a testament to our focus on quality and our dedication to our core values. #Achievement #Excellence",
      "Building a resilient supply chain is no longer optional; it's a strategic necessity. Here's how we're leveraging technology to ensure stability and growth. #SupplyChain #Tech",
      "Leadership isn't about being in charge; it's about taking care of those in your charge. Proud of the collaborative culture we've built. #CompanyCulture #Leadership"
    ],
    "Hype": [
      "We are disrupting the market! 🚀 Our latest release is officially out and the initial feedback is phenomenal. Join us in redefining what's possible in the industry.",
      "The future of work is here. We are thrilled to launch our new platform that empowers teams to achieve more than ever before. Let's build something incredible!",
      "Big announcement today! We've partnered with industry leaders to bring a new standard of service to our clients. The synergy is incredible. #Innovation #Partnership",
      "Scaling at 300% YoY! 📈 Our team is crushing goals and we're just getting warmed up. Looking forward to what the next quarter brings. #GrowthMindset #Success",
      "We're setting a new benchmark for excellence. Our latest project is live and it's a total game-changer for the sector. Don't get left behind! 🔥"
    ],
    "Inspirational": [
      "Success is a journey of persistence, not a destination of luck. To everyone grinding today: keep going. Your hard work is paving the way for your future self.",
      "In a world of algorithms, never forget the power of human connection. The most valuable asset in any business is the people who believe in the mission. ✨",
      "The greatest risk is not taking one. In an evolving economy, the only strategy that is guaranteed to fail is not taking risks. Embrace the challenge.",
      "Leadership is an opportunity to serve. When you empower others to reach their full potential, you elevate the entire organization. #Empowerment #Inspiration",
      "Don't let what you cannot do interfere with what you can do. Focus on your strengths and build a team that complements your weaknesses. 💫"
    ],
    "Luxury": [
      "True luxury in business is having a team you can trust implicitly. We pride ourselves on providing high-fidelity service to our elite clientele. #LuxuryBusiness #Trust",
      "Excellence is the foundation of everything we do. From the boardroom to the final product, we maintain the highest standards of sophistication. ✨",
      "A legacy of quality. We don't just build products; we build experiences that resonate with those who appreciate the finer things in life. #PremiumBrand",
      "Bespoke solutions for a modern world. We believe that true value lies in the details and the personalized approach we bring to every client. 🥂",
      "Elegance in execution. Our commitment to high-fidelity results ensures that our clients always experience the pinnacle of professional service."
    ],
    "Spiritual": [
      "Grateful for the opportunity to lead with integrity and purpose. When our work aligns with our values, we find a deeper sense of fulfillment in our professional lives. 🙏",
      "Leading with grace and compassion creates a work environment where everyone can thrive. Let's focus on building a more mindful and supportive business community.",
      "Every challenge in the workplace is an opportunity for spiritual and professional growth. Trust the process and stay committed to your higher calling. ✨",
      "Finding purpose in our work transforms a job into a mission. Blessed to be working with a team that shares a vision of making a positive impact on the world.",
      "A spirit of service is the heart of true leadership. When we focus on helping others succeed, we find our own path to lasting success. 🕊️"
    ]
  }
};

const HASHTAG_BANK = {
  "Professional": ["business", "strategy", "growth", "leadership", "success", "marketing", "entrepreneur", "productivity", "goals", "innovation", "management", "career", "professional", "network", "scaling", "results", "excellence", "planning", "mindset", "focus"],
  "Hype": ["hype", "launch", "exclusive", "limited", "trending", "viral", "fire", "energy", "gamechanger", "future", "now", "today", "alert", "mustsee", "unstoppable", "winning", "success", "motivation", "grind", "impact"],
  "Inspirational": ["motivation", "inspiration", "mindset", "success", "growth", "believe", "vision", "positivity", "journey", "dream", "goals", "persistence", "strength", "change", "purpose", "hope", "light", "faith", "potential", "wisdom"],
  "Luxury": ["luxury", "lifestyle", "elegance", "premium", "quality", "sophistication", "exclusive", "style", "design", "classy", "wealth", "prestige", "boutique", "elite", "refined", "timeless", "perfection", "craftsmanship", "curated", "bespoke"],
  "Spiritual": ["faith", "blessed", "spirituality", "grace", "purpose", "divine", "peace", "gratitude", "prayer", "hope", "light", "purpose", "wisdom", "soul", "mindfulness", "universe", "journey", "love", "community", "amen"]
};
