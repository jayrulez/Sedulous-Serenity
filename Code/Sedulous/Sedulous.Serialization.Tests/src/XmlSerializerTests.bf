using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.Xml;
using Sedulous.Xml;

namespace Sedulous.Serialization.Tests;

class XmlSerializerTests
{
	[Test]
	public static void TestWritePrimitives()
	{
		let serializer = XmlSerializer.CreateWriter();
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
		Test.Assert(output.Contains("hello"));
		Test.Assert(output.Contains("bool"));
		Test.Assert(output.Contains("true"));
	}

	[Test]
	public static void TestRoundTripPrimitives()
	{
		// Write
		let writer = XmlSerializer.CreateWriter();
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
		let doc = scope XmlDocument();
		let parseResult = doc.Parse(output);
		Test.Assert(parseResult == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
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
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		TestData writeData = original;
		Test.Assert(writer.Object("data", ref writeData) == .Ok);

		let output = scope String();
		writer.GetOutput(output);

		// Parse
		let doc = scope XmlDocument();
		let parseResult = doc.Parse(output);
		Test.Assert(parseResult == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
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
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		NestedData writeData = original;
		Test.Assert(writer.Object("data", ref writeData) == .Ok);

		let output = scope String();
		writer.GetOutput(output);

		// Parse
		let doc = scope XmlDocument();
		let parseResult = doc.Parse(output);
		Test.Assert(parseResult == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
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
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		List<int32> writeInts = scope .() { 1, 2, 3, 4, 5 };
		List<float> writeFloats = scope .() { 1.1f, 2.2f, 3.3f };

		writer.ArrayInt32("ints", writeInts);
		writer.ArrayFloat("floats", writeFloats);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope XmlDocument();
		let parseResult = doc.Parse(output);
		Test.Assert(parseResult == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
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
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		float[3] writePosition = .(1.0f, 2.0f, 3.0f);
		int32[4] writeIndices = .(10, 20, 30, 40);

		writer.FixedFloatArray("position", &writePosition[0], 3);
		writer.FixedInt32Array("indices", &writeIndices[0], 4);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope XmlDocument();
		let parseResult = doc.Parse(output);
		Test.Assert(parseResult == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
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
		let doc = scope XmlDocument();
		doc.Parse("<root><int32 name=\"something\">42</int32></root>");

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		int32 value = 0;
		Test.Assert(reader.Int32("nonexistent", ref value) == .FieldNotFound);
	}

	[Test]
	public static void TestHasField()
	{
		let doc = scope XmlDocument();
		doc.Parse("<root><int32 name=\"myField\">42</int32></root>");

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		Test.Assert(reader.HasField("myField"));
		Test.Assert(!reader.HasField("otherField"));
	}

	[Test]
	public static void TestRoundTripAllPrimitiveTypes()
	{
		// Write all primitive types
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		int8 writeInt8 = -8;
		int16 writeInt16 = -16;
		int32 writeInt32 = -32;
		int64 writeInt64 = -64;
		uint8 writeUInt8 = 8;
		uint16 writeUInt16 = 16;
		uint32 writeUInt32 = 32;
		uint64 writeUInt64 = 64;
		float writeFloat = 1.5f;
		double writeDouble = 2.5;

		writer.Int8("int8", ref writeInt8);
		writer.Int16("int16", ref writeInt16);
		writer.Int32("int32", ref writeInt32);
		writer.Int64("int64", ref writeInt64);
		writer.UInt8("uint8", ref writeUInt8);
		writer.UInt16("uint16", ref writeUInt16);
		writer.UInt32("uint32", ref writeUInt32);
		writer.UInt64("uint64", ref writeUInt64);
		writer.Float("float", ref writeFloat);
		writer.Double("double", ref writeDouble);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope XmlDocument();
		Test.Assert(doc.Parse(output) == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		int8 readInt8 = 0;
		int16 readInt16 = 0;
		int32 readInt32 = 0;
		int64 readInt64 = 0;
		uint8 readUInt8 = 0;
		uint16 readUInt16 = 0;
		uint32 readUInt32 = 0;
		uint64 readUInt64 = 0;
		float readFloat = 0;
		double readDouble = 0;

		Test.Assert(reader.Int8("int8", ref readInt8) == .Ok);
		Test.Assert(reader.Int16("int16", ref readInt16) == .Ok);
		Test.Assert(reader.Int32("int32", ref readInt32) == .Ok);
		Test.Assert(reader.Int64("int64", ref readInt64) == .Ok);
		Test.Assert(reader.UInt8("uint8", ref readUInt8) == .Ok);
		Test.Assert(reader.UInt16("uint16", ref readUInt16) == .Ok);
		Test.Assert(reader.UInt32("uint32", ref readUInt32) == .Ok);
		Test.Assert(reader.UInt64("uint64", ref readUInt64) == .Ok);
		Test.Assert(reader.Float("float", ref readFloat) == .Ok);
		Test.Assert(reader.Double("double", ref readDouble) == .Ok);

		// Verify values
		Test.Assert(readInt8 == writeInt8);
		Test.Assert(readInt16 == writeInt16);
		Test.Assert(readInt32 == writeInt32);
		Test.Assert(readInt64 == writeInt64);
		Test.Assert(readUInt8 == writeUInt8);
		Test.Assert(readUInt16 == writeUInt16);
		Test.Assert(readUInt32 == writeUInt32);
		Test.Assert(readUInt64 == writeUInt64);
		Test.Assert(Math.Abs(readFloat - writeFloat) < 0.001f);
		Test.Assert(Math.Abs(readDouble - writeDouble) < 0.001);
	}

	[Test]
	public static void TestRoundTripStringArray()
	{
		// Write
		let writer = XmlSerializer.CreateWriter();
		defer delete writer;

		List<String> writeStrings = scope .();
		writeStrings.Add(scope:: .("first"));
		writeStrings.Add(scope:: .("second"));
		writeStrings.Add(scope:: .("third"));

		writer.ArrayString("strings", writeStrings);

		let output = scope String();
		writer.GetOutput(output);

		// Parse and read
		let doc = scope XmlDocument();
		Test.Assert(doc.Parse(output) == .Ok);

		let reader = XmlSerializer.CreateReader(doc);
		defer delete reader;

		List<String> readStrings = scope .();
		defer { for (let s in readStrings) delete s; }

		Test.Assert(reader.ArrayString("strings", readStrings) == .Ok);

		// Verify
		Test.Assert(readStrings.Count == writeStrings.Count);
		for (int i = 0; i < readStrings.Count; i++)
			Test.Assert(readStrings[i] == writeStrings[i]);
	}

	[Test]
	public static void TestXmlOutputFormat()
	{
		let serializer = XmlSerializer.CreateWriter();
		defer delete serializer;

		int32 intVal = 42;
		serializer.Int32("testField", ref intVal);

		let output = scope String();
		serializer.GetOutput(output);

		// Verify XML structure
		Test.Assert(output.Contains("<root>"));
		Test.Assert(output.Contains("</root>"));
		Test.Assert(output.Contains("<int32"));
		Test.Assert(output.Contains("name=\"testField\""));
		Test.Assert(output.Contains("42"));
	}
}
