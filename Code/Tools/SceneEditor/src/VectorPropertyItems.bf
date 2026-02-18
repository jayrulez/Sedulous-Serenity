namespace SceneEditor;

using System;
using Sedulous.Mathematics;
using Sedulous.GUI;

/// PropertyItem for Vector2 fields with inline NumericUpDown editors.
class Vector2PropertyItem : PropertyItem
{
	public delegate Vector2() ValueGetter ~ delete _;
	public delegate void(Vector2) ValueSetter ~ delete _;

	private NumericUpDown mX;
	private NumericUpDown mY;
	private bool mUpdating = false;

	public this(StringView name, delegate Vector2() getter, delegate void(Vector2) setter) : base(name, .Float)
	{
		ValueGetter = getter;
		ValueSetter = setter;
	}

	public override UIElement CreateEditorControl()
	{
		let grid = new Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.RowDefinitions.Add(new .() { Height = .Star });

		mX = CreateSpinbox();
		GridProperties.SetColumn(mX, 0);
		grid.AddChild(mX);

		mY = CreateSpinbox();
		GridProperties.SetColumn(mY, 1);
		grid.AddChild(mY);

		// Initialize values
		if (ValueGetter != null)
		{
			let v = ValueGetter();
			mUpdating = true;
			mX.Value = v.X;
			mY.Value = v.Y;
			mUpdating = false;
		}

		return grid;
	}

	public override void RefreshEditorControl()
	{
		if (ValueGetter == null || mX == null) return;
		mUpdating = true;
		let v = ValueGetter();
		mX.Value = v.X;
		mY.Value = v.Y;
		mUpdating = false;
	}

	private NumericUpDown CreateSpinbox()
	{
		let nud = new NumericUpDown();
		nud.DecimalPlaces = 3;
		nud.Step = 0.1;
		nud.ValueChanged.Subscribe(new (n, val) => OnSpinboxChanged());
		return nud;
	}

	private void OnSpinboxChanged()
	{
		if (mUpdating) return;
		if (ValueSetter == null) return;
		let v = Vector2((float)mX.Value, (float)mY.Value);
		ValueSetter(v);
		OwnerGrid?.NotifyPropertyChanged(this);
	}
}

/// PropertyItem for Vector3 fields with inline NumericUpDown editors.
class Vector3PropertyItem : PropertyItem
{
	public delegate Vector3() ValueGetter ~ delete _;
	public delegate void(Vector3) ValueSetter ~ delete _;

	private NumericUpDown mX;
	private NumericUpDown mY;
	private NumericUpDown mZ;
	private bool mUpdating = false;

	public this(StringView name, delegate Vector3() getter, delegate void(Vector3) setter) : base(name, .Float)
	{
		ValueGetter = getter;
		ValueSetter = setter;
	}

	public override UIElement CreateEditorControl()
	{
		let grid = new Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.RowDefinitions.Add(new .() { Height = .Star });

		mX = CreateSpinbox();
		GridProperties.SetColumn(mX, 0);
		grid.AddChild(mX);

		mY = CreateSpinbox();
		GridProperties.SetColumn(mY, 1);
		grid.AddChild(mY);

		mZ = CreateSpinbox();
		GridProperties.SetColumn(mZ, 2);
		grid.AddChild(mZ);

		// Initialize values
		if (ValueGetter != null)
		{
			let v = ValueGetter();
			mUpdating = true;
			mX.Value = v.X;
			mY.Value = v.Y;
			mZ.Value = v.Z;
			mUpdating = false;
		}

		return grid;
	}

	public override void RefreshEditorControl()
	{
		if (ValueGetter == null || mX == null) return;
		mUpdating = true;
		let v = ValueGetter();
		mX.Value = v.X;
		mY.Value = v.Y;
		mZ.Value = v.Z;
		mUpdating = false;
	}

	private NumericUpDown CreateSpinbox()
	{
		let nud = new NumericUpDown();
		nud.DecimalPlaces = 3;
		nud.Step = 0.1;
		nud.ValueChanged.Subscribe(new (n, val) => OnSpinboxChanged());
		return nud;
	}

	private void OnSpinboxChanged()
	{
		if (mUpdating) return;
		if (ValueSetter == null) return;
		let v = Vector3((float)mX.Value, (float)mY.Value, (float)mZ.Value);
		ValueSetter(v);
		OwnerGrid?.NotifyPropertyChanged(this);
	}
}

/// PropertyItem for Vector4 fields with inline NumericUpDown editors.
class Vector4PropertyItem : PropertyItem
{
	public delegate Vector4() ValueGetter ~ delete _;
	public delegate void(Vector4) ValueSetter ~ delete _;

	private NumericUpDown mX;
	private NumericUpDown mY;
	private NumericUpDown mZ;
	private NumericUpDown mW;
	private bool mUpdating = false;

	public this(StringView name, delegate Vector4() getter, delegate void(Vector4) setter) : base(name, .Float)
	{
		ValueGetter = getter;
		ValueSetter = setter;
	}

	public override UIElement CreateEditorControl()
	{
		let grid = new Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.RowDefinitions.Add(new .() { Height = .Star });

		mX = CreateSpinbox();
		GridProperties.SetColumn(mX, 0);
		grid.AddChild(mX);

		mY = CreateSpinbox();
		GridProperties.SetColumn(mY, 1);
		grid.AddChild(mY);

		mZ = CreateSpinbox();
		GridProperties.SetColumn(mZ, 2);
		grid.AddChild(mZ);

		mW = CreateSpinbox();
		GridProperties.SetColumn(mW, 3);
		grid.AddChild(mW);

		// Initialize values
		if (ValueGetter != null)
		{
			let v = ValueGetter();
			mUpdating = true;
			mX.Value = v.X;
			mY.Value = v.Y;
			mZ.Value = v.Z;
			mW.Value = v.W;
			mUpdating = false;
		}

		return grid;
	}

	public override void RefreshEditorControl()
	{
		if (ValueGetter == null || mX == null) return;
		mUpdating = true;
		let v = ValueGetter();
		mX.Value = v.X;
		mY.Value = v.Y;
		mZ.Value = v.Z;
		mW.Value = v.W;
		mUpdating = false;
	}

	private NumericUpDown CreateSpinbox()
	{
		let nud = new NumericUpDown();
		nud.DecimalPlaces = 3;
		nud.Step = 0.1;
		nud.ValueChanged.Subscribe(new (n, val) => OnSpinboxChanged());
		return nud;
	}

	private void OnSpinboxChanged()
	{
		if (mUpdating) return;
		if (ValueSetter == null) return;
		let v = Vector4((float)mX.Value, (float)mY.Value, (float)mZ.Value, (float)mW.Value);
		ValueSetter(v);
		OwnerGrid?.NotifyPropertyChanged(this);
	}
}
