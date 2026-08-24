/// The backend base URL for all authenticated API calls.
///
/// The `API_BASE_URL` dart-define overrides the production default — point the
/// app at a local backend with
/// `--dart-define=API_BASE_URL=http://localhost:3000` (used for the Solar
/// Mirror walking-skeleton HITL run, adityas/ai/3–4).
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.84beings.com',
);
