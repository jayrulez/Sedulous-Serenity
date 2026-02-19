namespace SceneEditor;

using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.GUI;

/// PropertyItem for Vector3 color fields with a color swatch + R/G/B spinners.
class ColorPropertyItem : PropertyItem
{
	public delegate Vector3() ValueGetter ~ delete _;
	public delegate void(Vector3) ValueSetter ~ delete _;

	private ColorSwatch mSwatch;
	private NumericUpDown mR;
	private NumericUpDown mG;
	private NumericUpDown mB;
	private bool mUpdating = false;

	public this(StringView name, delegate Vector3() getter, delegate void(Vector3) setter) : base(name, .Color)
	{
		ValueGetter = getter;
		ValueSetter = setter;
	}

	public override UIElement CreateEditorControl()
	{
		let grid = new Grid();
		grid.ColumnDefinitions.Add(new .() { Width = .Pixels(24) });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.ColumnDefinitions.Add(new .() { Width = .Star });
		grid.RowDefinitions.Add(new .() { Height = .Star });

		mSwatch = new ColorSwatch();
		mSwatch.Owner = this;
		GridProperties.SetColumn(mSwatch, 0);
		grid.AddChild(mSwatch);

		mR = CreateSpinbox();
		GridProperties.SetColumn(mR, 1);
		grid.AddChild(mR);

		mG = CreateSpinbox();
		GridProperties.SetColumn(mG, 2);
		grid.AddChild(mG);

		mB = CreateSpinbox();
		GridProperties.SetColumn(mB, 3);
		grid.AddChild(mB);

		// Initialize values
		if (ValueGetter != null)
		{
			let v = ValueGetter();
			mUpdating = true;
			mR.Value = v.X;
			mG.Value = v.Y;
			mB.Value = v.Z;
			mUpdating = false;
			mSwatch.SwatchColor = Color(v.X, v.Y, v.Z);
		}

		return grid;
	}

	public override void RefreshEditorControl()
	{
		if (ValueGetter == null || mR == null) return;
		mUpdating = true;
		let v = ValueGetter();
		mR.Value = v.X;
		mG.Value = v.Y;
		mB.Value = v.Z;
		mSwatch.SwatchColor = Color(v.X, v.Y, v.Z);
		mUpdating = false;
	}

	private NumericUpDown CreateSpinbox()
	{
		let nud = new NumericUpDown();
		nud.Minimum = 0;
		nud.Maximum = 1;
		nud.DecimalPlaces = 2;
		nud.Step = 0.01;
		nud.ValueChanged.Subscribe(new (n, val) => OnSpinboxChanged());
		return nud;
	}

	private void OnSpinboxChanged()
	{
		if (mUpdating) return;
		if (ValueSetter == null) return;
		let v = Vector3((float)mR.Value, (float)mG.Value, (float)mB.Value);
		mSwatch.SwatchColor = Color(v.X, v.Y, v.Z);
		ValueSetter(v);
		OwnerGrid?.NotifyPropertyChanged(this);
	}

	/// Opens a Flyout with a ColorPickerPanel anchored to the swatch.
	private void OpenColorPicker()
	{
		if (mSwatch?.Context == null) return;

		let picker = new ColorPickerPanel();
		if (ValueGetter != null)
			picker.SetColor(ValueGetter());

		picker.ColorChanged.Subscribe(new (rgb) =>
		{
			mUpdating = true;
			mR.Value = rgb.X;
			mG.Value = rgb.Y;
			mB.Value = rgb.Z;
			mSwatch.SwatchColor = Color(rgb.X, rgb.Y, rgb.Z);
			mUpdating = false;
			if (ValueSetter != null)
				ValueSetter(rgb);
			OwnerGrid?.NotifyPropertyChanged(this);
		});

		let flyout = new Flyout();
		flyout.Content = picker;
		flyout.Placement = .Bottom;
		flyout.ShowAt(mSwatch);

		flyout.Closed.Subscribe(new (f) =>
		{
			mSwatch.Context?.QueueDelete(f);
		});
	}

	/// Small control that renders a filled color rectangle. Click to open picker.
	private class ColorSwatch : Control
	{
		public Color SwatchColor = Color.Black;
		public ColorPropertyItem Owner;

		protected override void RenderOverride(DrawContext ctx)
		{
			let ab = ArrangedBounds;
			let bounds = RectangleF(ab.X, ab.Y + 2, ab.Width, ab.Height - 4);
			ctx.FillRect(bounds, SwatchColor);
			ctx.DrawRect(bounds, Color(128, 128, 128), 1);
		}

		protected override void OnMouseDown(MouseButtonEventArgs e)
		{
			base.OnMouseDown(e);
			if (e.Button == .Left)
			{
				Owner?.OpenColorPicker();
				e.Handled = true;
			}
		}
	}
}
