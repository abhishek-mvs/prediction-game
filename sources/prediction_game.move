module prediction_game::prediction_game {
    use std::string::{String};
    use std::vector;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    /// Error codes
    const E_NOT_ADMIN: u64 = 1;
    const E_GAME_NOT_FOUND: u64 = 2;
    const E_GAME_ALREADY_ENDED: u64 = 3;
    const E_PREDICTION_PERIOD_ENDED: u64 = 4;
    const E_INSUFFICIENT_FUNDS: u64 = 5;
    const E_ALREADY_PREDICTED: u64 = 6;
    const E_GAME_NOT_ENDED: u64 = 7;
    const E_WINNER_ALREADY_DECLARED: u64 = 8;
    const E_INVALID_TEAM_ID: u64 = 9;
    const E_NO_PREDICTIONS: u64 = 10;

    /// Represents a team in the prediction game
    struct Team has store, drop, copy {
        id: u64,
        name: String,
        prediction_count: u64,
    }

    /// Represents a prediction made by a user
    struct Prediction has store, drop, copy {
        game_id: u64,
        user: address,
        team_id: u64,
        amount: u64,
        timestamp: u64,
    }

    /// Represents a prediction game
    struct Game has store, copy, drop {
        id: u64,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        teams: vector<Team>,
        predictions: vector<Prediction>,
        total_pool: u64,
        winner_team_id: u64,
        is_winner_declared: bool,
        is_distributed: bool,
    }

    /// Events
    struct GameCreatedEvent has drop, store {
        game_id: u64,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
    }

    struct PredictionMadeEvent has drop, store {
        game_id: u64,
        user: address,
        team_id: u64,
        amount: u64,
    }

    struct WinnerDeclaredEvent has drop, store {
        game_id: u64,
        winner_team_id: u64,
    }

    struct RewardDistributedEvent has drop, store {
        game_id: u64,
        winner: address,
        amount: u64,
    }

    /// Resource that stores the state of the prediction game
    struct PredictionGameState has key {
        admin: address,
        games: vector<Game>,
        game_counter: u64,
        treasury: Coin<AptosCoin>,
        
        // Events
        game_created_events: EventHandle<GameCreatedEvent>,
        prediction_made_events: EventHandle<PredictionMadeEvent>,
        winner_declared_events: EventHandle<WinnerDeclaredEvent>,
        reward_distributed_events: EventHandle<RewardDistributedEvent>,
    }

    /// Resource to track user's predictions
    struct UserPredictions has key {
        active_predictions: vector<Prediction>,
        past_predictions: vector<Prediction>,
    }

    /// Initialize the prediction game
    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        // Create the prediction game state
        move_to(admin, PredictionGameState {
            admin: admin_addr,
            games: vector::empty<Game>(),
            game_counter: 0,
            treasury: coin::zero<AptosCoin>(),
            game_created_events: account::new_event_handle<GameCreatedEvent>(admin),
            prediction_made_events: account::new_event_handle<PredictionMadeEvent>(admin),
            winner_declared_events: account::new_event_handle<WinnerDeclaredEvent>(admin),
            reward_distributed_events: account::new_event_handle<RewardDistributedEvent>(admin),
        });
    }

    /// Create a new prediction game (admin only)
    public entry fun create_game(
        admin: &signer,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        team_names: vector<String>
    ) acquires PredictionGameState {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<PredictionGameState>(admin_addr);
        
        // Verify admin
        assert!(admin_addr == state.admin, E_NOT_ADMIN);
        
        // Create teams
        let teams = vector::empty<Team>();
        let team_count = vector::length(&team_names);
        let i = 0;
        while (i < team_count) {
            let team_name = *vector::borrow(&team_names, i);
            vector::push_back(&mut teams, Team {
                id: i,
                name: team_name,
                prediction_count: 0,
            });
            i = i + 1;
        };
        
        // Create game
        let game_id = state.game_counter;
        let game = Game {
            id: game_id,
            title,
            prediction_end_time,
            contest_end_time,
            entry_price,
            teams,
            predictions: vector::empty<Prediction>(),
            total_pool: 0,
            winner_team_id: 0,
            is_winner_declared: false,
            is_distributed: false,
        };
        
        vector::push_back(&mut state.games, game);
        state.game_counter = state.game_counter + 1;
        
        // Emit event
        event::emit_event(
            &mut state.game_created_events,
            GameCreatedEvent {
                game_id,
                title,
                prediction_end_time,
                contest_end_time,
                entry_price,
            }
        );
    }

    /// Make a prediction for a game
    public entry fun make_prediction(
        user: &signer,
        game_id: u64,
        team_id: u64,
        amount: u64
    ) acquires PredictionGameState, UserPredictions {
        let user_addr = signer::address_of(user);
        let state = borrow_global_mut<PredictionGameState>(@prediction_game);
        
        // Find the game
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        let found = false;
        
        while (game_idx < games_len && !found) {
            let game = vector::borrow_mut(&mut state.games, game_idx);
            if (game.id == game_id) {
                found = true;
                
                // Check if prediction period is still active
                let current_time = timestamp::now_seconds();
                assert!(current_time <= game.prediction_end_time, E_PREDICTION_PERIOD_ENDED);
                
                // Check if game has ended
                assert!(current_time <= game.contest_end_time, E_GAME_ALREADY_ENDED);
                
                // Check if team_id is valid
                let teams_len = vector::length(&game.teams);
                assert!(team_id < teams_len, E_INVALID_TEAM_ID);
                
                // Check if user has already predicted for this game
                let predictions_len = vector::length(&game.predictions);
                let pred_idx = 0;
                let already_predicted = false;
                
                while (pred_idx < predictions_len && !already_predicted) {
                    let prediction = vector::borrow(&game.predictions, pred_idx);
                    if (prediction.user == user_addr) {
                        already_predicted = true;
                    };
                    pred_idx = pred_idx + 1;
                };
                
                assert!(!already_predicted, E_ALREADY_PREDICTED);
                
                // Check if user has enough funds
                assert!(amount >= game.entry_price, E_INSUFFICIENT_FUNDS);
                
                // Transfer funds
                let payment = coin::withdraw<AptosCoin>(user, game.entry_price);
                coin::merge(&mut state.treasury, payment);
                
                // Update game
                game.total_pool = game.total_pool + game.entry_price;
                
                // Update team prediction count
                let team = vector::borrow_mut(&mut game.teams, team_id);
                team.prediction_count = team.prediction_count + 1;
                
                // Create prediction
                let prediction = Prediction {
                    game_id,
                    user: user_addr,
                    team_id,
                    amount: game.entry_price,
                    timestamp: current_time,
                };
                
                // Add prediction to game
                vector::push_back(&mut game.predictions, prediction);
                
                // Add prediction to user's active predictions
                if (!exists<UserPredictions>(user_addr)) {
                    move_to(user, UserPredictions {
                        active_predictions: vector::empty<Prediction>(),
                        past_predictions: vector::empty<Prediction>(),
                    });
                };
                
                let user_predictions = borrow_global_mut<UserPredictions>(user_addr);
                vector::push_back(&mut user_predictions.active_predictions, prediction);
                
                // Emit event
                event::emit_event(
                    &mut state.prediction_made_events,
                    PredictionMadeEvent {
                        game_id,
                        user: user_addr,
                        team_id,
                        amount: game.entry_price,
                    }
                );
                
                break
            };
            game_idx = game_idx + 1;
        };
        
        assert!(found, E_GAME_NOT_FOUND);
    }

    /// Declare winner for a game (admin only)
    public entry fun declare_winner(
        admin: &signer,
        game_id: u64,
        winner_team_id: u64
    ) acquires PredictionGameState {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<PredictionGameState>(admin_addr);
        
        // Verify admin
        assert!(admin_addr == state.admin, E_NOT_ADMIN);
        
        // Find the game
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        let found = false;
        
        while (game_idx < games_len && !found) {
            let game = vector::borrow_mut(&mut state.games, game_idx);
            if (game.id == game_id) {
                found = true;
                
                // Check if game has ended
                let current_time = timestamp::now_seconds();
                assert!(current_time >= game.contest_end_time, E_GAME_NOT_ENDED);
                
                // Check if winner has already been declared
                assert!(!game.is_winner_declared, E_WINNER_ALREADY_DECLARED);
                
                // Check if team_id is valid
                let teams_len = vector::length(&game.teams);
                assert!(winner_team_id < teams_len, E_INVALID_TEAM_ID);
                
                // Update game
                game.winner_team_id = winner_team_id;
                game.is_winner_declared = true;
                
                // Emit event
                event::emit_event(
                    &mut state.winner_declared_events,
                    WinnerDeclaredEvent {
                        game_id,
                        winner_team_id,
                    }
                );
                
                break
            };
            game_idx = game_idx + 1;
        };
        
        assert!(found, E_GAME_NOT_FOUND);
    }

    /// Distribute rewards for a game (admin only)
    public entry fun distribute_rewards(
        admin: &signer,
        game_id: u64
    ) acquires PredictionGameState, UserPredictions {
        let admin_addr = signer::address_of(admin);
        let state = borrow_global_mut<PredictionGameState>(admin_addr);
        
        // Verify admin
        assert!(admin_addr == state.admin, E_NOT_ADMIN);
        
        // Find the game
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        let found = false;
        
        while (game_idx < games_len && !found) {
            let game = vector::borrow_mut(&mut state.games, game_idx);
            if (game.id == game_id) {
                found = true;
                
                // Check if winner has been declared
                assert!(game.is_winner_declared, E_GAME_NOT_ENDED);
                
                // Check if rewards have already been distributed
                assert!(!game.is_distributed, E_GAME_ALREADY_ENDED);
                
                // Calculate admin fee (1%)
                let admin_fee = game.total_pool / 100;
                let remaining_pool = game.total_pool - admin_fee;
                
                // Find winners
                let predictions_len = vector::length(&game.predictions);
                let winner_count = 0;
                let pred_idx = 0;
                
                // Count winners
                while (pred_idx < predictions_len) {
                    let prediction = vector::borrow(&game.predictions, pred_idx);
                    if (prediction.team_id == game.winner_team_id) {
                        winner_count = winner_count + 1;
                    };
                    pred_idx = pred_idx + 1;
                };
                
                assert!(winner_count > 0, E_NO_PREDICTIONS);
                
                // Calculate reward per winner
                let reward_per_winner = remaining_pool / winner_count;
                
                // Distribute rewards
                pred_idx = 0;
                while (pred_idx < predictions_len) {
                    let prediction = vector::borrow(&game.predictions, pred_idx);
                    if (prediction.team_id == game.winner_team_id) {
                        // Transfer reward to winner
                        let reward = coin::extract(&mut state.treasury, reward_per_winner);
                        coin::deposit(prediction.user, reward);
                        
                        // Update user's predictions
                        if (exists<UserPredictions>(prediction.user)) {
                            let user_predictions = borrow_global_mut<UserPredictions>(prediction.user);
                            
                            // Move prediction from active to past
                            let active_len = vector::length(&user_predictions.active_predictions);
                            let active_idx = 0;
                            
                            while (active_idx < active_len) {
                                let active_pred = vector::borrow(&user_predictions.active_predictions, active_idx);
                                if (active_pred.game_id == game_id) {
                                    let removed_pred = vector::remove(&mut user_predictions.active_predictions, active_idx);
                                    vector::push_back(&mut user_predictions.past_predictions, removed_pred);
                                    break
                                };
                                active_idx = active_idx + 1;
                            };
                        };
                        
                        // Emit event
                        event::emit_event(
                            &mut state.reward_distributed_events,
                            RewardDistributedEvent {
                                game_id,
                                winner: prediction.user,
                                amount: reward_per_winner,
                            }
                        );
                    };
                    pred_idx = pred_idx + 1;
                };
                
                // Mark game as distributed
                game.is_distributed = true;
                
                break
            };
            game_idx = game_idx + 1;
        };
        
        assert!(found, E_GAME_NOT_FOUND);
    }

    #[view]
    /// Get active games
    public fun get_active_games(): vector<Game> acquires PredictionGameState {
        let state = borrow_global<PredictionGameState>(@prediction_game);
        let active_games = vector::empty<Game>();
        let current_time = timestamp::now_seconds();
        
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        
        while (game_idx < games_len) {
            let game = vector::borrow(&state.games, game_idx);
            if (current_time <= game.contest_end_time && !game.is_distributed) {
                vector::push_back(&mut active_games, *game);
            };
            game_idx = game_idx + 1;
        };
        
        active_games
    }

    #[view]
    /// Get game details
    public fun get_game_details(game_id: u64): Game acquires PredictionGameState {
        let state = borrow_global<PredictionGameState>(@prediction_game);
        
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        
        while (game_idx < games_len) {
            let game = vector::borrow(&state.games, game_idx);
            if (game.id == game_id) {
                return *game
            };
            game_idx = game_idx + 1;
        };
        
        abort E_GAME_NOT_FOUND
    }

    #[view]
    /// Get user's active predictions
    public fun get_user_active_predictions(user_addr: address): vector<Prediction> acquires UserPredictions {
        if (!exists<UserPredictions>(user_addr)) {
            return vector::empty<Prediction>()
        };
        
        let user_predictions = borrow_global<UserPredictions>(user_addr);
        *&user_predictions.active_predictions
    }

    #[view]
    /// Get user's past predictions
    public fun get_user_past_predictions(user_addr: address): vector<Prediction> acquires UserPredictions {
        if (!exists<UserPredictions>(user_addr)) {
            return vector::empty<Prediction>()
        };
        
        let user_predictions = borrow_global<UserPredictions>(user_addr);
        *&user_predictions.past_predictions
    }

    #[view]
    /// Get leaderboard (users with most wins)
    public fun get_leaderboard(): vector<address> acquires PredictionGameState {
        let state = borrow_global<PredictionGameState>(@prediction_game);
        let winners = vector::empty<address>();
        
        let games_len = vector::length(&state.games);
        let game_idx = 0;
        
        while (game_idx < games_len) {
            let game = vector::borrow(&state.games, game_idx);
            if (game.is_distributed) {
                let predictions_len = vector::length(&game.predictions);
                let pred_idx = 0;
                
                while (pred_idx < predictions_len) {
                    let prediction = vector::borrow(&game.predictions, pred_idx);
                    if (prediction.team_id == game.winner_team_id) {
                        vector::push_back(&mut winners, prediction.user);
                    };
                    pred_idx = pred_idx + 1;
                };
            };
            game_idx = game_idx + 1;
        };
        
        winners
    }
    
    /// Helper function to check if a game has been distributed
    public fun is_game_distributed(game: &Game): bool {
        game.is_distributed
    }
    
    /// Helper function to check if a winner has been declared for a game
    public fun is_winner_declared(game: &Game): bool {
        game.is_winner_declared
    }
    
    /// Helper function to get the teams of a game
    public fun get_game_teams(game: &Game): vector<Team> {
        game.teams
    }
    
    /// Helper function to create a game with 2 teams
    public entry fun create_game_with_2_teams(
        admin: &signer,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        team1_name: String,
        team2_name: String
    ) acquires PredictionGameState {
        let team_names = vector::empty<String>();
        vector::push_back(&mut team_names, team1_name);
        vector::push_back(&mut team_names, team2_name);
        
        create_game(admin, title, prediction_end_time, contest_end_time, entry_price, team_names);
    }
    
    /// Helper function to create a game with 3 teams
    public entry fun create_game_with_3_teams(
        admin: &signer,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        team1_name: String,
        team2_name: String,
        team3_name: String
    ) acquires PredictionGameState {
        let team_names = vector::empty<String>();
        vector::push_back(&mut team_names, team1_name);
        vector::push_back(&mut team_names, team2_name);
        vector::push_back(&mut team_names, team3_name);
        
        create_game(admin, title, prediction_end_time, contest_end_time, entry_price, team_names);
    }
    
    /// Helper function to create a game with 4 teams
    public entry fun create_game_with_4_teams(
        admin: &signer,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        team1_name: String,
        team2_name: String,
        team3_name: String,
        team4_name: String
    ) acquires PredictionGameState {
        let team_names = vector::empty<String>();
        vector::push_back(&mut team_names, team1_name);
        vector::push_back(&mut team_names, team2_name);
        vector::push_back(&mut team_names, team3_name);
        vector::push_back(&mut team_names, team4_name);
        
        create_game(admin, title, prediction_end_time, contest_end_time, entry_price, team_names);
    }
    
    /// Helper function to create a game with teams specified as a comma-separated string
    /// Example: "Team A,Team B,Team C,Team D"
    public entry fun create_game_with_csv_teams(
        admin: &signer,
        title: String,
        prediction_end_time: u64,
        contest_end_time: u64,
        entry_price: u64,
        csv_team_names: String
    ) acquires PredictionGameState {
        let team_names = vector::empty<String>();
        let bytes = *std::string::bytes(&csv_team_names);
        let len = vector::length(&bytes);
        
        // Parse CSV team names
        let start_idx = 0;
        let i = 0;
        
        while (i <= len) {
            // Reached end of string or comma delimiter
            if (i == len || *vector::borrow(&bytes, i) == 0x2C) { // 0x2C is ASCII for comma
                if (i > start_idx) {
                    // Extract the team name from start_idx to i-1
                    let team_bytes = vector::empty<u8>();
                    let j = start_idx;
                    while (j < i) {
                        vector::push_back(&mut team_bytes, *vector::borrow(&bytes, j));
                        j = j + 1;
                    };
                    
                    // Create string and add to team names
                    let team_name = std::string::utf8(team_bytes);
                    vector::push_back(&mut team_names, team_name);
                };
                
                start_idx = i + 1;
            };
            
            i = i + 1;
        };
        
        create_game(admin, title, prediction_end_time, contest_end_time, entry_price, team_names);
    }

    #[view]
    /// Check if a game identified by game_id has been distributed
    public fun check_game_distributed(game_id: u64): bool acquires PredictionGameState {
        let game = get_game_details(game_id);
        game.is_distributed
    }
    
    #[view]
    /// Check if a winner has been declared for a game identified by game_id
    public fun check_winner_declared(game_id: u64): bool acquires PredictionGameState {
        let game = get_game_details(game_id);
        game.is_winner_declared
    }
    
    #[view]
    /// Get teams for a game identified by game_id
    public fun get_teams_for_game(game_id: u64): vector<Team> acquires PredictionGameState {
        let game = get_game_details(game_id);
        game.teams
    }
} 