using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class InputFilterTests
{
	[Test]
	public static void Filter_None_AcceptsEverything()
	{
		let f = scope InputFilter();
		Test.Assert(f.Accept('a'));
		Test.Assert(f.Accept('5'));
		Test.Assert(f.Accept('#'));
		Test.Assert(f.Accept(' '));
	}

	[Test]
	public static void Filter_Digits_AcceptsDigitsOnly()
	{
		let f = scope InputFilter();
		f.Mode = .Digits;
		Test.Assert(f.Accept('0'));
		Test.Assert(f.Accept('5'));
		Test.Assert(f.Accept('9'));
		Test.Assert(!f.Accept('a'));
		Test.Assert(!f.Accept('Z'));
		Test.Assert(!f.Accept('#'));
		Test.Assert(!f.Accept(' '));
	}

	[Test]
	public static void Filter_HexDigits_AcceptsHexOnly()
	{
		let f = scope InputFilter();
		f.Mode = .HexDigits;
		Test.Assert(f.Accept('0'));
		Test.Assert(f.Accept('9'));
		Test.Assert(f.Accept('a'));
		Test.Assert(f.Accept('f'));
		Test.Assert(f.Accept('A'));
		Test.Assert(f.Accept('F'));
		Test.Assert(!f.Accept('g'));
		Test.Assert(!f.Accept('G'));
		Test.Assert(!f.Accept('#'));
	}

	[Test]
	public static void Filter_Custom_UsesDelegate()
	{
		let f = scope InputFilter();
		f.SetCustomFilter(new (c) => c == 'x' || c == 'y');
		Test.Assert(f.Accept('x'));
		Test.Assert(f.Accept('y'));
		Test.Assert(!f.Accept('z'));
		Test.Assert(!f.Accept('a'));
	}

	[Test]
	public static void Filter_StaticFactories()
	{
		let digits = InputFilter.Digits();
		defer delete digits;
		Test.Assert(digits.Mode == .Digits);
		Test.Assert(digits.Accept('5'));
		Test.Assert(!digits.Accept('a'));

		let hex = InputFilter.HexDigits();
		defer delete hex;
		Test.Assert(hex.Mode == .HexDigits);
		Test.Assert(hex.Accept('f'));
		Test.Assert(!hex.Accept('g'));
	}
}
