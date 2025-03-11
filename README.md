# Prediction Game Smart Contract

A Move smart contract for Movement Labs that allows users to predict the outcome of events and win rewards.

## Overview

This prediction game allows:

1. An admin to create prediction games with multiple teams
2. Users to make predictions by paying an entry fee
3. Admin to declare winners and distribute rewards
4. Users to view active games, their predictions, and leaderboards

## Contract Structure

The contract consists of the following key components:

### Resources

- `PredictionGameState`: Stores all games, admin info, and treasury
- `UserPredictions`: Tracks a user's active and past predictions

### Structs

- `Game`: Represents a prediction game with teams and predictions
- `Team`: Represents a team in a game
- `Prediction`: Represents a user's prediction

### Key Functions

#### Admin Functions

- `initialize`: Initialize the prediction game contract
- `create_game`: Create a new prediction game
- `declare_winner`: Declare the winning team for a game
- `distribute_rewards`: Distribute rewards to winners

#### User Functions

- `make_prediction`: Make a prediction for a game

#### View Functions

- `get_active_games`: Get all active games
- `get_game_details`: Get details of a specific game
- `get_user_active_predictions`: Get a user's active predictions
- `get_user_past_predictions`: Get a user's past predictions
- `get_leaderboard`: Get the leaderboard of winners

## How It Works

1. Admin initializes the contract and creates games with teams
2. Users connect their wallets and make predictions by paying the entry fee
3. After the game ends, admin declares the winning team
4. Admin distributes rewards to users who predicted correctly
5. Admin receives a 1% fee from the total pool

## Testing

Run the tests with:

```bash
aptos move test
```

## Deployment

1. Update the `Move.toml` file with your account address
2. Deploy the contract:

```bash
aptos move publish
```

3. Initialize the contract:

```bash
aptos move run --function-id <YOUR_ADDRESS>::prediction_game::initialize
```

## License

MIT 