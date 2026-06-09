export const NARRATIVES = {
  labels: [
    '26.03.26',
    '27.03.26',
    '27.03.26',
    '27.03.26',
    '27.03.26',
    '27.03.26',
    '27.03.26',
    '27.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '28.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '29.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '30.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '31.03.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '01.04.26',
    '02.04.26',
    '02.04.26',
    '02.04.26',
    '02.04.26',
    '02.04.26',
    '02.04.26',
    '02.04.26',
  ],
  datasets: [
    {
      label: 'Iran war',
      topics: 'negotiations,ceasefire,iranians,plants,kharg',
      description:
        'Social posts debate the U.S.–Iran conflict after Trump signaled a possible ceasefire but also threatened further strikes, including seizing Kharg oil hub and targeting Iran’s power infrastructure. Tweets highlight contradictions (humanitarian passage vs. U.S. blocks), accusations of regime‑change failure, casualties, videos mocking the U.S., and geopolitical winners (China, Russia). Market uncertainty and accusations of political market manipulation are noted alongside Iran’s diplomatic messaging to Americans.',
      data: [
        9, 31, 25, 26, 8, 9, 9, 15, 25, 33, 14, 31, 47, 11, 13, 20, 15, 25, 22, 20, 21, 20, 14, 21,
        33, 24, 17, 6, 10, 18, 17, 16, 23, 29, 11, 21, 27, 16, 46, 42, 59, 123, 28, 16, 27, 15, 37,
        35, 19, 13, 18, 11, 40, 22, 9,
      ],
    },
    {
      label: 'Quantum threat to crypto',
      topics: 'postquantum,computing,computers,cryptography,encryption',
      description:
        'Conversation focuses on the risk future quantum computers pose to elliptic-curve cryptography (ECDSA/ECC) that secures Bitcoin and Ethereum, amplified by a Google Quantum AI paper tailoring Shor’s algorithm to 256-bit ECDLP. Views split between dismissing it as FUD and urgent warnings (claims keys could be cracked in minutes/days), prompting calls for post‑quantum wallet/signature standards, migration plans, and interim mitigations (e.g., locking dormant Satoshi addresses). Projects like Solana highlight existing quantum-resistant features, and many see post‑quantum upgrades as both a necessary defense and an opportunity for differentiation.',
      data: [
        13, 12, 11, 13, 15, 25, 12, 8, 13, 34, 26, 15, 26, 5, 9, 17, 14, 16, 11, 13, 14, 7, 9, 22,
        15, 16, 9, 14, 4, 7, 13, 15, 31, 20, 19, 11, 24, 132, 30, 36, 21, 33, 17, 14, 4, 12, 15, 32,
        7, 8, 14, 13, 24, 18, 25,
      ],
    },
    {
      label: 'BTC price',
      topics: '65k,60k,66k,trendline,70k',
      description:
        'Market chatter centers on a Bitcoin pullback below $70K driven by geopolitical risk and risk-off flows, with traders watching $65–66K as near-term support and $60K (and a worst-case $45K) as deeper targets. Technical notes: BTC is testing an 8‑year trendline, showing rejections around the $69–76K resistance band, inside-bar price action on higher timeframes, rising OI and short interest into support. Participants discuss DCA opportunities, potential large buys (e.g., Saylor), and broader volatility spillover to ETH, SOL and token airdrops—raising caution for token launches in a bearish environment.',
      data: [
        9, 3, 17, 9, 13, 45, 35, 19, 14, 12, 20, 19, 7, 33, 16, 28, 21, 10, 10, 13, 8, 23, 14, 9, 7,
        2, 29, 27, 30, 8, 1, 9, 8, 7, 5, 14, 27, 19, 20, 25, 7, 11, 18, 13, 10, 12, 23, 9, 19, 27,
        23, 14, 14, 4, 5,
      ],
    },
    {
      label: 'AI agents',
      topics: 'autonomous,autonomously,creativity,loops,replace',
      description:
        'Discussion centers on the rise of autonomous AI agents and an emerging agent-to-agent economy: agents transacting, self-upgrading, and getting dedicated wallets/budgets (Coinbase embedded wallets, USDC on Base, Ampersend). Key themes include job disruption and workforce reskilling (possible blue-collar boom vs white-collar displacement), security and trust needs for on-chain skill stores (partnerships like Pieverse), rising AI misbehavior, infrastructure trends (Codex Desktop, local models reducing provider dependence), and concerns about energy use and long-term governance.',
      data: [
        7, 64, 18, 13, 12, 4, 22, 15, 13, 20, 16, 14, 15, 17, 21, 21, 9, 18, 17, 9, 13, 8, 11, 22,
        29, 20, 12, 11, 16, 4, 17, 18, 12, 7, 16, 14, 14, 8, 14, 17, 11, 16, 10, 10, 17, 16, 26, 25,
        12, 4, 18, 15, 10, 16, 19,
      ],
    },
    {
      label: 'SOL',
      topics: 'solanas,katana,solana,dex,sol',
      description:
        'Social chatter is focused on Solana ($SOL) price action, on-chain volume, and trading opportunities. Users cite massive spot/DEX activity (e.g., ~$13.6B weekly DEX volume, $58M daily token volume, claims of 98% tokenized-equities flow), memecoin-driven extraction and retail losses, and comparisons to Ethereum’s earlier cycle. Opinions split between bullish adoption/yield narratives (more transactions via Jito, staking/Stable Pool buying, stablecoin looping and yield growth by 2026) and bearish concerns (downtrend from $200–$240, memecoin drain, short setups and resistance at $85–$200). Traders discuss specific setups, support targets ($76–$80 buy zone), risk management, and profit-taking strategies.',
      data: [
        21, 5, 7, 10, 15, 14, 19, 15, 7, 12, 15, 17, 11, 20, 8, 13, 11, 8, 5, 11, 6, 9, 16, 13, 8,
        20, 13, 21, 10, 7, 12, 10, 4, 12, 10, 10, 15, 5, 4, 16, 8, 5, 17, 49, 11, 14, 9, 4, 16, 22,
        11, 21, 5, 9, 5,
      ],
    },
    {
      label: 'Bitcoin as money',
      topics: 'bitcoiners,monetary,physics,immutable,opt',
      description:
        'Tweets promote Bitcoin as hard money and a hedge against fiat, urging cold storage and holding unwrapped while highlighting scarcity and personal priorities. Conversations cover wrapping vs unwrapped Bitcoin, potential real-world use cases (proof/change of ownership, real estate), community culture (hardliners, maximalists vs innovation maximalists), educational content, and Bitcoin-themed merchandise.',
      data: [
        7, 7, 4, 9, 13, 38, 6, 12, 10, 9, 11, 6, 12, 10, 10, 8, 9, 6, 6, 7, 8, 6, 9, 21, 14, 10, 11,
        11, 3, 10, 11, 11, 7, 9, 11, 12, 5, 6, 12, 11, 4, 4, 8, 9, 14, 10, 4, 13, 9, 8, 18, 7, 6, 8,
        13,
      ],
    },
    {
      label: 'Stablecoins',
      topics: 'polygon,stablecoins,apy,0xpolygon,stablecoin',
      description:
        'Social chatter centers on stablecoins becoming the backbone of crypto markets and enterprise finance: they now account for ~83% of USD-denominated spot volume, Polygon has massive stablecoin txn activity, and firms are building payroll, settlement, and treasury use-cases (KRW PoC, Stellar, Zebec, Kaia). Conversation highlights yield innovation (USDD recursive vaults, protocols offering APYs, lending markets like Aave/Venus), exchange incentives (USD1 rewards), and growing institutional adoption while regulatory questions and CBDC competition remain. Market dynamics are also discussed—large onchain flows, liquidity shifts, and recent stablecoin market cap contractions—framing stablecoins as a CFO and enterprise concern.',
      data: [
        6, 6, 9, 8, 13, 1, 11, 10, 6, 7, 6, 9, 6, 2, 12, 10, 6, 7, 4, 4, 9, 12, 3, 8, 9, 10, 9, 10,
        9, 8, 9, 9, 9, 14, 13, 7, 7, 3, 12, 6, 3, 5, 5, 7, 48, 6, 4, 3, 7, 12, 16, 9, 3, 7, 17,
      ],
    },
    {
      label: 'Memecoins',
      topics: 'memecoins,memecoin,memes,meme,wojak',
      description:
        'Community discussion centers on memecoin hype, heavy shilling and tactics to get early access (telegram groups, follow-to-DM, filter-based trades). Many argue the memecoin game is “solved” and the market is overheated, though a few projects (e.g., $BELLS, WOJAK, RAGE, PEPE) are singled out for scarcity or breakout potential. Debates focus on utility vs “vibes,” fragmented liquidity from many deploys, and proposals to curb multi-wallet abuse on platforms to restore fair launches. Memecoins are also viewed as marketing tools for creators (awareness campaigns, prints/merch), fueling nostalgia for a “golden age” and calls for new mechanics to restart parabolic moves.',
      data: [
        12, 6, 5, 2, 7, 4, 9, 5, 16, 8, 7, 6, 4, 3, 5, 17, 3, 5, 3, 6, 8, 6, 7, 4, 4, 9, 8, 10, 6,
        106, 9, 7, 9, 5, 13, 8, 8, 3, 9, 3, 8, 4, 1, 8, 1, 7, 4, 8, 11, 8, 6, 9, 5, 6, 4,
      ],
    },
    {
      label: 'Oil price',
      topics: 'barrel,surge,crude,cl,110',
      description:
        'Social chatter centers on a sharp rally in crude oil—WTI topping $100–108+/barrel—driven by OPEC+ cut fears, US Strategic Petroleum Reserve draws (55M+ barrels), and geopolitical risk (Strait of Hormuz, war concerns). Traders debate whether futures justify spot moves, with bullish calls ranging to $200–$500 and worries about rising transport costs, inflation, and equity market impacts. Market sentiment is mixed: some are long and expect more upside, others warn volatility and the macro downside if oil spikes further.',
      data: [
        1, 2, 4, 6, 4, 6, 1, 11, 5, 7, 14, 6, 2, 0, 5, 5, 5, 2, 7, 8, 5, 9, 1, 7, 8, 2, 6, 11, 4, 9,
        4, 5, 4, 82, 3, 4, 31, 7, 6, 5, 4, 3, 10, 3, 9, 6, 2, 4, 13, 6, 5, 2, 7, 2, 5,
      ],
    },
    {
      label: 'Gaming',
      topics: 'gaming,games,gamers,steam,game',
      description:
        'Discussion focuses on a Web3 gaming revival and GameFi activity: new launches and indie titles (TheGrottoL1, PlayZap, Color Pop Quest), token-driven rewards ($PZP, $FUN) and developer updates. Threads highlight partnerships for cross-chain and scalable deployment (PlaysOut×qubetics, N7 Alliance), debates against “ponzinomics,” and calls to prioritize core gameplay over pure play-to-earn models. Market signals (top gainers, mobile launches) and broader tech trends (AI tailwinds for gaming platforms) underline growing investor and community interest.',
      data: [
        6, 3, 5, 4, 10, 4, 6, 6, 7, 2, 4, 2, 2, 4, 9, 8, 3, 14, 38, 7, 6, 4, 6, 4, 5, 1, 4, 5, 11,
        5, 3, 2, 10, 5, 6, 24, 4, 9, 4, 1, 9, 4, 6, 5, 6, 2, 3, 12, 5, 6, 11, 12, 10, 3, 5,
      ],
    },
    {
      label: 'China',
      topics: 'chinas,china,taiwan,chinese,ccp',
      description:
        'Discussion frames China as a rising strategic rival across geopolitics, trade and technology: export controls (rare earths), trade investigations, missile deployments, cyber operations, and gold retention; meanwhile China is accelerating domestic chips, AI models (Qwen/GLM), and infrastructure innovations. Market and supply‑chain effects are highlighted (soaring rare‑earth stocks, production shifts to Vietnam, altered trade dependence), with commentators seeing Beijing poised to gain as US credibility falters.',
      data: [
        6, 2, 10, 4, 4, 3, 7, 9, 4, 7, 5, 7, 10, 7, 4, 9, 1, 6, 4, 2, 6, 7, 1, 15, 4, 10, 7, 4, 3,
        4, 7, 4, 10, 9, 9, 15, 5, 7, 5, 10, 9, 3, 4, 0, 10, 12, 7, 7, 6, 8, 6, 5, 7, 3, 5,
      ],
    },
    {
      label: 'Memescope Monday',
      topics: 'memescope,scope,monday,orangie,trenching',
      description:
        'Social chatter centers on “Memescope Monday” — a meme-token launch/marketing trend that some celebrate as hype/legendary (Elon tweet, banger starts) while many are confused and critical. Comparisons to 2020 DeFi summer, mentions of related events like “Quantum Tuesday,” and strong warnings about rug pulls, deployer advantages, and clown-fiesta behavior dominate the conversation.',
      data: [
        3, 4, 1, 7, 7, 4, 4, 2, 2, 4, 5, 6, 3, 5, 6, 6, 10, 8, 13, 12, 4, 4, 10, 1, 6, 5, 2, 8, 5,
        65, 13, 1, 5, 5, 6, 1, 2, 2, 6, 0, 2, 9, 7, 5, 5, 2, 2, 2, 6, 15, 3, 5, 3, 7, 5,
      ],
    },
    {
      label: 'Japanese twitter surge',
      topics: 'japanese,japan,tokyo,japans,culture',
      description:
        'Twitter threads show strong enthusiasm for Japanese users and culture—travel plans, community cross-pollination with American and Korean audiences, and hyperbolic “Japanmaxxing” fandom—alongside warnings that algorithm changes could fragment these connections. Technical/crypto discussion highlights Tokyo’s trading infrastructure advantage (Tokyo ~15.9ms vs Amsterdam ~221ms on Hyperliquid probes) and mentions BDACS + Ripple enabling KRW1 deployment at scale in 2026. Overall mix of social community growth and latency/infra updates relevant to traders and builders.',
      data: [
        5, 6, 2, 4, 7, 7, 6, 3, 5, 9, 5, 4, 2, 6, 6, 6, 7, 12, 6, 7, 9, 5, 5, 2, 22, 5, 6, 3, 16, 1,
        2, 10, 14, 7, 7, 7, 0, 2, 4, 3, 8, 3, 1, 3, 3, 4, 5, 10, 4, 8, 8, 7, 6, 2, 3,
      ],
    },
    {
      label: 'Precious metals',
      topics: 'silver,platinum,gold,plunges,forex',
      description:
        'Twitter chatter focuses on intense volatility in gold and silver driven by geopolitical risk, shifting rate expectations, and supply/demand notes (including preordered silver sets). Prices have seen large swings—silver off from its ATH but record quarter close, gold bouncing around $4,400–$4,700—while analysts (Goldman, UBS) issue lofty 2026 targets. Technicals are mixed (100MA/Kumo resistance, possible breakout zones), miners remain weak, and futures volume (notably on MEXC) has surged, amplifying moves.',
      data: [
        4, 3, 8, 1, 5, 5, 3, 2, 9, 4, 10, 9, 6, 12, 4, 8, 4, 8, 1, 20, 1, 7, 4, 3, 5, 2, 1, 4, 9, 1,
        5, 3, 4, 9, 0, 15, 14, 7, 1, 9, 15, 7, 3, 10, 6, 9, 4, 2, 6, 5, 4, 1, 9, 2, 4,
      ],
    },
    {
      label: 'Bear market is here',
      topics: 'bear,bears,bull,bearish,millionaires',
      description:
        'Social posts focus on navigating the crypto bear market: survival mindset, accumulation and DCA, resisting overtrading, and using the downturn to build skills, networks, and projects. Users share humor and lifestyle tradeoffs (selling assets, bodybuilding, hobbies) and warn about exploits and team exits during bear phases. Several thread posts include a personal accumulation list (XRP, LINK, QNT, HBAR) and emphasize that surviving now leads to outsized gains in the next bull market.',
      data: [
        6, 1, 3, 6, 74, 1, 19, 2, 4, 5, 7, 4, 5, 3, 4, 4, 4, 2, 6, 8, 1, 2, 2, 5, 4, 6, 2, 3, 1, 30,
        4, 3, 7, 4, 7, 4, 4, 1, 4, 5, 3, 2, 2, 1, 6, 11, 3, 2, 1, 4, 3, 1, 4, 1, 6,
      ],
    },
    {
      label: 'Trump going ballistic',
      topics: 'losers,hang,aka,loser,pedo',
      description:
        'Twitter threads strongly criticize Donald Trump’s presidency as erratic, self-serving, and deceptive. Users highlight his contradictory statements, performative rhetoric (gold comments, ‘mission from God’), claims about cognitive testing, alleged misuse of public funds for war, and strategic unpredictability (’12D chess’), expressing concern about political and national consequences.',
      data: [
        3, 6, 1, 2, 5, 4, 5, 9, 4, 5, 4, 4, 4, 5, 6, 7, 3, 1, 6, 9, 11, 1, 9, 6, 6, 5, 6, 5, 9, 8,
        2, 7, 1, 4, 2, 3, 7, 8, 7, 2, 6, 5, 5, 3, 9, 5, 3, 13, 6, 14, 4, 1, 8, 3, 4,
      ],
    },
    {
      label: 'Tesla',
      topics: 'fsd,tesla,car,cars,driving',
      description:
        'Social chatter centers on Tesla’s advancing autonomy and production innovations. Users share firsthand FSD experiences (some claiming flawless, hands-off trips) while others note safety/regulatory risks and skepticism about rapid Robotaxi deployment. Discussion highlights Tesla’s v14.3 software milestone, compute/supply bottlenecks limiting FSD rollout, Gigacasting manufacturing gains, and reactions to Model S/X end-of-production.',
      data: [
        3, 5, 2, 5, 5, 3, 5, 12, 0, 2, 2, 6, 4, 14, 2, 5, 4, 9, 4, 5, 0, 1, 6, 3, 2, 3, 7, 4, 9, 2,
        3, 3, 4, 10, 2, 3, 2, 5, 2, 6, 11, 9, 7, 6, 2, 7, 2, 2, 4, 4, 5, 4, 4, 2, 5,
      ],
    },
    {
      label: 'Six red months for BTC',
      topics: '6th,consecutive,candles,candle,row',
      description:
        'Twitter is focused on Bitcoin’s monthly close as it approaches a potential sixth consecutive red monthly candle—only seen once before (2018). Traders and analysts are debating whether March will flip green or cement the sixth loss, citing historical post-2018 rallies, technical patterns, portfolio pain, price targets, and the risk of an unprecedented 7th red month in April. Community sentiment mixes hopium, bearish caution, live analysis, and prediction contests tied to the monthly close.',
      data: [
        6, 1, 2, 6, 2, 7, 2, 6, 33, 6, 0, 10, 3, 1, 13, 4, 4, 2, 1, 3, 4, 5, 3, 1, 1, 0, 0, 1, 2, 3,
        23, 4, 3, 2, 1, 2, 9, 2, 22, 3, 2, 2, 2, 4, 2, 6, 1, 3, 10, 2, 1, 3, 1, 2, 2,
      ],
    },
    {
      label: 'Art',
      topics: 'artists,art,artist,gallery,artwork',
      description:
        'Community art share showcasing diverse works (hand-painted, acrylics, fore-edge, sand-in-glass, AI-generated) and promoting free artist exposure. Discussion highlights a slowing digital art market even as some teams open physical gallery space, and raises the core question: what gives a digital collectible its value? Notes Ordinals’ presence in major auctions, upcoming indexing on raster_art, Candy Digital project, and references to 2021 Ethereum NFT minting and art-world value dynamics (e.g., Van Gogh).',
      data: [
        6, 1, 23, 13, 3, 3, 7, 0, 6, 1, 4, 3, 7, 0, 5, 3, 7, 3, 4, 3, 7, 1, 4, 4, 2, 3, 7, 4, 4, 3,
        5, 4, 4, 11, 3, 7, 5, 3, 2, 1, 3, 3, 1, 2, 1, 6, 2, 1, 4, 0, 4, 6, 1, 7, 5,
      ],
    },
  ],
}
