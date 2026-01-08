using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Extension methods for animating UIElement properties.
public static class UIElementAnimations
{
	/// Fades the element's opacity from one value to another.
	public static FloatAnimation FadeOpacity(UIElement element, float from, float to, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.Opacity = value; };
		return anim;
	}

	/// Fades the element in (opacity 0 to 1).
	public static FloatAnimation FadeIn(UIElement element, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		return FadeOpacity(element, 0, 1, duration, easing);
	}

	/// Fades the element out (opacity 1 to 0).
	public static FloatAnimation FadeOut(UIElement element, float duration = 0.3f, EasingType easing = .QuadraticIn)
	{
		return FadeOpacity(element, 1, 0, duration, easing);
	}

	/// Animates the element's margin.
	public static ThicknessAnimation AnimateMargin(UIElement element, Thickness from, Thickness to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new ThicknessAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.Margin = value; };
		return anim;
	}

	/// Animates the element's padding.
	public static ThicknessAnimation AnimatePadding(UIElement element, Thickness from, Thickness to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new ThicknessAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.Padding = value; };
		return anim;
	}

	/// Animates the element's width.
	public static FloatAnimation AnimateWidth(UIElement element, float from, float to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.Width = value; };
		return anim;
	}

	/// Animates the element's height.
	public static FloatAnimation AnimateHeight(UIElement element, float from, float to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.Height = value; };
		return anim;
	}

	/// Animates the element's min width.
	public static FloatAnimation AnimateMinWidth(UIElement element, float from, float to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.MinWidth = value; };
		return anim;
	}

	/// Animates the element's min height.
	public static FloatAnimation AnimateMinHeight(UIElement element, float from, float to, float duration = 0.3f, EasingType easing = .QuadraticInOut)
	{
		let anim = new FloatAnimation(from, to);
		anim.Duration = duration;
		anim.Easing = easing;
		anim.OnValueChanged = new (value) => { element.MinHeight = value; };
		return anim;
	}

	/// Slides the element in from the left using margin animation.
	public static ThicknessAnimation SlideInFromLeft(UIElement element, float distance = 50, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		let currentMargin = element.Margin;
		let fromMargin = Thickness(currentMargin.Left - distance, currentMargin.Top, currentMargin.Right, currentMargin.Bottom);
		element.Margin = fromMargin;
		element.Opacity = 0;

		let anim = AnimateMargin(element, fromMargin, currentMargin, duration, easing);

		// Also fade in
		let fadeAnim = FadeIn(element, duration, easing);
		element.Context?.Animations.Add(fadeAnim);

		return anim;
	}

	/// Slides the element in from the right using margin animation.
	public static ThicknessAnimation SlideInFromRight(UIElement element, float distance = 50, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		let currentMargin = element.Margin;
		let fromMargin = Thickness(currentMargin.Left, currentMargin.Top, currentMargin.Right - distance, currentMargin.Bottom);
		element.Margin = fromMargin;
		element.Opacity = 0;

		let anim = AnimateMargin(element, fromMargin, currentMargin, duration, easing);

		let fadeAnim = FadeIn(element, duration, easing);
		element.Context?.Animations.Add(fadeAnim);

		return anim;
	}

	/// Slides the element in from the top using margin animation.
	public static ThicknessAnimation SlideInFromTop(UIElement element, float distance = 50, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		let currentMargin = element.Margin;
		let fromMargin = Thickness(currentMargin.Left, currentMargin.Top - distance, currentMargin.Right, currentMargin.Bottom);
		element.Margin = fromMargin;
		element.Opacity = 0;

		let anim = AnimateMargin(element, fromMargin, currentMargin, duration, easing);

		let fadeAnim = FadeIn(element, duration, easing);
		element.Context?.Animations.Add(fadeAnim);

		return anim;
	}

	/// Slides the element in from the bottom using margin animation.
	public static ThicknessAnimation SlideInFromBottom(UIElement element, float distance = 50, float duration = 0.3f, EasingType easing = .QuadraticOut)
	{
		let currentMargin = element.Margin;
		let fromMargin = Thickness(currentMargin.Left, currentMargin.Top, currentMargin.Right, currentMargin.Bottom - distance);
		element.Margin = fromMargin;
		element.Opacity = 0;

		let anim = AnimateMargin(element, fromMargin, currentMargin, duration, easing);

		let fadeAnim = FadeIn(element, duration, easing);
		element.Context?.Animations.Add(fadeAnim);

		return anim;
	}
}
