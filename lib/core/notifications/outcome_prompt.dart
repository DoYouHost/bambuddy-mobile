import 'launch_relay.dart';

/// "How did this print come out?" waiting for the app shell to ask it (#1898),
/// as an archive id. Posted from two places — the server's
/// `print_confirm_request` frame while the app is on screen, and a tap on the
/// outcome notification — and opened in one, the shell.
final outcomePrompts = LaunchRelay<int>();
