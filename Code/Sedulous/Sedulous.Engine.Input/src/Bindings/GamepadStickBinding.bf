namespace Sedulous.Engine.Input;

using System;
using Sedulous.Shell.Input;
using Sedulous.Serialization;
using Sedulous.Mathematics;

/// Which gamepad stick to use.
enum GamepadStick
{
	Left,
	Right
}

/// Binding for a gamepad stick (combines X and Y axes into Vector2).
class GamepadStickBinding : InputBinding
{
	/// Which stick to bind.
	public GamepadStick Stick = .Left;

	/// Gamepad index (0-based).
	public int32 GamepadIndex = 0;

	/// Dead zone threshold (0.0 to 1.0).
	public float DeadZone = 0.15f;

	/// Whether to invert the X axis.
	public bool InvertX = false;

	/// Whether to invert the Y axis.
	public bool InvertY = false;

	/// Sensitivity multiplier.
	public float Sensitivity = 1.0f;

	public this()
	{
	}

	public this(GamepadStick stick, int32 gamepadIndex = 0, float deadZone = 0.15f)
	{
		Stick = stick;
		GamepadIndex = gamepadIndex;
		DeadZone = deadZone;
		UpdateDisplayName();
	}

	public override InputSource Source => .Gamepad;

	public override InputValue GetValue(IInputManager input)
	{
		let gamepad = input.GetGamepad(GamepadIndex);
		if (gamepad == null || !gamepad.Connected)
			return .FromVector2(0, 0);

		float rawX, rawY;
		if (Stick == .Left)
		{
			rawX = gamepad.GetAxis(.LeftX);
			rawY = gamepad.GetAxis(.LeftY);
		}
		else
		{
			rawX = gamepad.GetAxis(.RightX);
			rawY = gamepad.GetAxis(.RightY);
		}

		// Apply circular dead zone
		var stick = Vector2(rawX, rawY);
		float magnitude = stick.Length();

		if (magnitude < DeadZone)
			return .FromVector2(0, 0);

		// Remap magnitude from [deadzone, 1] to [0, 1]
		float normalizedMagnitude = (magnitude - DeadZone) / (1.0f - DeadZone);
		stick = Vector2.Normalize(stick) * normalizedMagnitude;

		// Apply inversion and sensitivity
		if (InvertX) stick.X = -stick.X;
		if (InvertY) stick.Y = -stick.Y;
		stick *= Sensitivity;

		return .FromVector2(stick);
	}

	public override bool WasPressed(IInputManager input)
	{
		// Consider "pressed" when stick moves outside dead zone
		let value = GetValue(input).AsVector2;
		return value.Length() > 0.1f;
	}

	public override bool WasReleased(IInputManager input)
	{
		return false; // Analog inputs don't have discrete release
	}

	protected override void UpdateDisplayName()
	{
		DisplayName.Clear();
		if (Stick == .Left)
			DisplayName.Set("Left Stick");
		else
			DisplayName.Set("Right Stick");
	}

	public override InputBinding Clone()
	{
		return new GamepadStickBinding(Stick, GamepadIndex, DeadZone)
		{
			InvertX = InvertX,
			InvertY = InvertY,
			Sensitivity = Sensitivity
		};
	}

	public override int32 SerializationVersion => 1;

	public override SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		var stick = (int32)Stick;
		result = serializer.Int32("stick", ref stick);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Stick = (GamepadStick)stick;

		result = serializer.Int32("gamepadIndex", ref GamepadIndex);
		if (result != .Ok)
			return result;

		result = serializer.Float("deadZone", ref DeadZone);
		if (result != .Ok)
			return result;

		result = serializer.Float("sensitivity", ref Sensitivity);
		if (result != .Ok)
			return result;

		int32 flags = 0;
		if (InvertX) flags |= 1;
		if (InvertY) flags |= 2;
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
		{
			InvertX = (flags & 1) != 0;
			InvertY = (flags & 2) != 0;
			UpdateDisplayName();
		}

		return .Ok;
	}
}
