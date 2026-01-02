using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;

namespace Sedulous.Serialization.Tests;

/// Test class implementing ISerializable
class TestData : ISerializable
{
	public int32 IntValue;
	public float FloatValue;
	public String StringValue = new .() ~ delete _;
	public bool BoolValue;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		var result = s.Int32("intValue", ref IntValue);
		if (result != .Ok) return result;

		result = s.Float("floatValue", ref FloatValue);
		if (result != .Ok) return result;

		result = s.String("stringValue", StringValue);
		if (result != .Ok) return result;

		result = s.Bool("boolValue", ref BoolValue);
		if (result != .Ok) return result;

		return .Ok;
	}
}

/// Nested test class
class NestedData : ISerializable
{
	public int32 Value;
	public TestData Child = new .() ~ delete _;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s)
	{
		var result = s.Int32("value", ref Value);
		if (result != .Ok) return result;

		result = s.Object("child", ref Child);
		if (result != .Ok) return result;

		return .Ok;
	}
}

class SerializerTests
{
	[Test]
	public static void TestWritePrimitives()
	{
		let serializer = OpenDDLSerializer.CreateWriter();
		defer delete serializer;

		int32 intVal = 42;
		float floatVal = 3.14f;
		String strVal = scope .("hello");
		bool boolVal = true;

		Test.Assert(serializer.Int32("myInt", ref intVal) == .Ok);
		Test.Assert(serializer.Float("myFloat", ref floatVal) == .Ok);
		Test.Assert(serializer.String("myString", strVal) == .Ok);
		Test.Assert(serializer.Bool("myBool", ref boolVal) == .Ok);

		let output = scope String();
		serializer.GetOutput(output);

		// Verify output contains expected data
		Test.Assert(output.Contains("int32"));
		Test.Assert(output.Contains("42"));
		Test.Assert(output.Contains("float"));
		Test.Assert(output.Contains("string"));
		Test.Assert(output.Contains("\"hello\""));
		Test.Assert(output.Contains("bool"));
		Test.Assert(output.Contains("true"));
	}

	[Test]
	public static void TestRoundTripPrimitives()
	{
		// Write
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 writeInt = 42;
		float writeFloat = 3.14f;
		String writeStr = scope .("hello world");
		bool writeBool = true;

		writer.Int32("myInt", ref writeInt);
		writer.Float("myFloat", ref writeFloat);
		writer.String("myString", writeStr);
		writer.Bool("myBool", ref writeBool);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope DataDescription();
		let parseResult = doc.ParseText(output);
		Test.Assert(parseResult == .Ok);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 readInt = 0;
		float readFloat = 0;
		String readStr = scope .();
		bool readBool = false;

		Test.Assert(reader.Int32("myInt", ref readInt) == .Ok);
		Test.Assert(reader.Float("myFloat", ref readFloat) == .Ok);
		Test.Assert(reader.String("myString", readStr) == .Ok);
		Test.Assert(reader.Bool("myBool", ref readBool) == .Ok);

		// Verify values match
		Test.Assert(readInt == writeInt);
		Test.Assert(Math.Abs(readFloat - writeFloat) < 0.001f);
		Test.Assert(readStr == writeStr);
		Test.Assert(readBool == writeBool);
	}

	[Test]
	public static void TestRoundTripObject()
	{
		// Create test data
		let original = scope TestData();
		original.IntValue = 123;
		original.FloatValue = 2.5f;
		original.StringValue.Set("test string");
		original.BoolValue = true;

		// Write
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		TestData writeData = original;
		Test.Assert(writer.Object("data", ref writeData) == .Ok);

		let output = scope String();
		writer.GetOutput(output);

		// Parse with SerializableDataDescription which keeps "Obj_" structures
		let doc = scope SerializableDataDescription();
		let parseResult = doc.ParseText(output);
		Test.Assert(parseResult == .Ok);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		TestData readData = null;
		Test.Assert(reader.Object("data", ref readData) == .Ok);
		defer delete readData;

		// Verify values match
		Test.Assert(readData.IntValue == original.IntValue);
		Test.Assert(Math.Abs(readData.FloatValue - original.FloatValue) < 0.001f);
		Test.Assert(readData.StringValue == original.StringValue);
		Test.Assert(readData.BoolValue == original.BoolValue);
	}

	[Test]
	public static void TestRoundTripNestedObject()
	{
		// Create test data
		let original = scope NestedData();
		original.Value = 99;
		original.Child.IntValue = 42;
		original.Child.FloatValue = 1.5f;
		original.Child.StringValue.Set("nested");
		original.Child.BoolValue = false;

		// Write
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		NestedData writeData = original;
		Test.Assert(writer.Object("data", ref writeData) == .Ok);

		let output = scope String();
		writer.GetOutput(output);

		// Parse with SerializableDataDescription which keeps "Obj_" structures
		let doc = scope SerializableDataDescription();
		let parseResult = doc.ParseText(output);
		Test.Assert(parseResult == .Ok);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		NestedData readData = null;
		Test.Assert(reader.Object("data", ref readData) == .Ok);
		defer delete readData;

		// Verify values match
		Test.Assert(readData.Value == original.Value);
		Test.Assert(readData.Child.IntValue == original.Child.IntValue);
		Test.Assert(Math.Abs(readData.Child.FloatValue - original.Child.FloatValue) < 0.001f);
		Test.Assert(readData.Child.StringValue == original.Child.StringValue);
		Test.Assert(readData.Child.BoolValue == original.Child.BoolValue);
	}

	[Test]
	public static void TestRoundTripArrays()
	{
		// Write
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		List<int32> writeInts = scope .() { 1, 2, 3, 4, 5 };
		List<float> writeFloats = scope .() { 1.1f, 2.2f, 3.3f };

		writer.ArrayInt32("ints", writeInts);
		writer.ArrayFloat("floats", writeFloats);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope DataDescription();
		let parseResult = doc.ParseText(output);
		Test.Assert(parseResult == .Ok);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		List<int32> readInts = scope .();
		List<float> readFloats = scope .();

		Test.Assert(reader.ArrayInt32("ints", readInts) == .Ok);
		Test.Assert(reader.ArrayFloat("floats", readFloats) == .Ok);

		// Verify arrays match
		Test.Assert(readInts.Count == writeInts.Count);
		for (int i = 0; i < readInts.Count; i++)
			Test.Assert(readInts[i] == writeInts[i]);

		Test.Assert(readFloats.Count == writeFloats.Count);
		for (int i = 0; i < readFloats.Count; i++)
			Test.Assert(Math.Abs(readFloats[i] - writeFloats[i]) < 0.001f);
	}

	[Test]
	public static void TestRoundTripFixedArrays()
	{
		// Write
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		float[3] writePosition = .(1.0f, 2.0f, 3.0f);
		int32[4] writeIndices = .(10, 20, 30, 40);

		writer.FixedFloatArray("position", &writePosition[0], 3);
		writer.FixedInt32Array("indices", &writeIndices[0], 4);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope DataDescription();
		let parseResult = doc.ParseText(output);
		Test.Assert(parseResult == .Ok);

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		float[3] readPosition = .();
		int32[4] readIndices = .();

		Test.Assert(reader.FixedFloatArray("position", &readPosition[0], 3) == .Ok);
		Test.Assert(reader.FixedInt32Array("indices", &readIndices[0], 4) == .Ok);

		// Verify arrays match
		for (int i = 0; i < 3; i++)
			Test.Assert(Math.Abs(readPosition[i] - writePosition[i]) < 0.001f);

		for (int i = 0; i < 4; i++)
			Test.Assert(readIndices[i] == writeIndices[i]);
	}

	[Test]
	public static void TestFieldNotFound()
	{
		let doc = scope DataDescription();
		doc.ParseText("int32 $something {42}");

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 value = 0;
		Test.Assert(reader.Int32("nonexistent", ref value) == .FieldNotFound);
	}

	[Test]
	public static void TestHasField()
	{
		let doc = scope DataDescription();
		doc.ParseText("int32 $myField {42}");

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		Test.Assert(reader.HasField("myField"));
		Test.Assert(!reader.HasField("otherField"));
	}
}
