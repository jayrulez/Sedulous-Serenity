namespace StormTactics.Client;

using System;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;
using Sedulous.Core.Core;

delegate void LoginSuccessDelegate();

/// Login/Register screen for server mode.
class LoginScreen
{
	private Grid mRoot ~ delete _;
	private TextBox mUsernameBox;
	private TextBox mPasswordBox;
	private TextBlock mStatusLabel;
	private Button mLoginButton;
	private Button mRegisterButton;
	private ServerSaveManager mServerSave;

	private EventAccessor<LoginSuccessDelegate> mOnLoginSuccess = new .() ~ delete _;
	public EventAccessor<LoginSuccessDelegate> OnLoginSuccess => mOnLoginSuccess;
	public UIElement RootElement => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.Background = Color(12, 14, 22, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;
		mRoot.RowDefinitions.Add(new .() { Height = .Star });
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });

		// Center panel
		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Spacing = 16;
		panel.HorizontalAlignment = .Center;
		panel.VerticalAlignment = .Center;
		panel.Width = .Fixed(320);

		// Title
		let title = new TextBlock("STORM TACTICS");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 28;
		title.TextAlignment = .Center;
		title.HorizontalAlignment = .Center;
		panel.AddChild(title);

		let subtitle = new TextBlock("Server Login");
		subtitle.Foreground = Color(160, 160, 180);
		subtitle.FontSize = 16;
		subtitle.TextAlignment = .Center;
		subtitle.HorizontalAlignment = .Center;
		panel.AddChild(subtitle);

		// Spacer
		let spacer = new Border();
		spacer.Height = .Fixed(16);
		panel.AddChild(spacer);

		// Username
		let userLabel = new TextBlock("Username");
		userLabel.Foreground = Color(180, 180, 200);
		userLabel.FontSize = 14;
		panel.AddChild(userLabel);

		mUsernameBox = new TextBox();
		mUsernameBox.Placeholder = "Enter username...";
		mUsernameBox.Height = .Fixed(32);
		mUsernameBox.HorizontalAlignment = .Stretch;
		mUsernameBox.MaxLength = 32;
		panel.AddChild(mUsernameBox);

		// Password
		let passLabel = new TextBlock("Password");
		passLabel.Foreground = Color(180, 180, 200);
		passLabel.FontSize = 14;
		panel.AddChild(passLabel);

		mPasswordBox = new TextBox();
		mPasswordBox.Placeholder = "Enter password...";
		mPasswordBox.Height = .Fixed(32);
		mPasswordBox.HorizontalAlignment = .Stretch;
		mPasswordBox.MaxLength = 64;
		panel.AddChild(mPasswordBox);

		// Spacer
		let spacer2 = new Border();
		spacer2.Height = .Fixed(8);
		panel.AddChild(spacer2);

		// Buttons row
		let btnRow = new StackPanel();
		btnRow.Orientation = .Horizontal;
		btnRow.Spacing = 12;
		btnRow.HorizontalAlignment = .Center;

		mLoginButton = new Button();
		mLoginButton.Width = .Fixed(140);
		mLoginButton.Height = .Fixed(40);
		mLoginButton.Background = Color(60, 120, 140);
		let loginLabel = new TextBlock("LOGIN");
		loginLabel.Foreground = Color.White;
		loginLabel.FontSize = 16;
		loginLabel.TextAlignment = .Center;
		loginLabel.HorizontalAlignment = .Center;
		loginLabel.IsHitTestVisible = false;
		mLoginButton.Content = loginLabel;
		btnRow.AddChild(mLoginButton);

		mRegisterButton = new Button();
		mRegisterButton.Width = .Fixed(140);
		mRegisterButton.Height = .Fixed(40);
		mRegisterButton.Background = Color(100, 160, 60);
		let regLabel = new TextBlock("REGISTER");
		regLabel.Foreground = Color.White;
		regLabel.FontSize = 16;
		regLabel.TextAlignment = .Center;
		regLabel.HorizontalAlignment = .Center;
		regLabel.IsHitTestVisible = false;
		mRegisterButton.Content = regLabel;
		btnRow.AddChild(mRegisterButton);

		panel.AddChild(btnRow);

		// Status label
		mStatusLabel = new TextBlock("");
		mStatusLabel.Foreground = Color(200, 80, 80);
		mStatusLabel.FontSize = 14;
		mStatusLabel.TextAlignment = .Center;
		mStatusLabel.HorizontalAlignment = .Center;
		panel.AddChild(mStatusLabel);

		mRoot.AddChild(panel);
	}

	/// Wire the login/register button callbacks.
	public void SetCallbacks(ServerSaveManager serverSave)
	{
		mServerSave = serverSave;

		mLoginButton.Click.Subscribe(new (btn) =>
		{
			let username = scope String(mUsernameBox.Text);
			let password = scope String(mPasswordBox.Text);

			if (username.IsEmpty || password.IsEmpty)
			{
				SetStatus("Please enter username and password", true);
				return;
			}

			SetStatus("Logging in...", false);
			if (mServerSave.Login(username, password) case .Ok)
			{
				SetStatus("Success!", false);
				mOnLoginSuccess.[Friend]Invoke();
			}
			else
			{
				SetStatus("Login failed — check credentials", true);
			}
		});

		mRegisterButton.Click.Subscribe(new (btn) =>
		{
			let username = scope String(mUsernameBox.Text);
			let password = scope String(mPasswordBox.Text);

			if (username.IsEmpty || password.Length < 3)
			{
				SetStatus("Username required, password min 3 chars", true);
				return;
			}

			SetStatus("Registering...", false);
			if (mServerSave.Register(username, password) case .Ok)
			{
				SetStatus("Registered successfully!", false);
				mOnLoginSuccess.[Friend]Invoke();
			}
			else
			{
				SetStatus("Registration failed — name may be taken", true);
			}
		});
	}

	/// Set the status message.
	public void SetStatus(StringView text, bool isError)
	{
		mStatusLabel.Text = text;
		mStatusLabel.Foreground = isError ? Color(200, 80, 80) : Color(100, 200, 100);
	}
}
