using System;

namespace Sedulous.Mathematics;

/// A 3x3 matrix stored in column-major order.
///
/// Memory layout (column-major, OpenGL compatible):
/// Column 0: M11, M21, M31
/// Column 1: M12, M22, M32
/// Column 2: M13, M23, M33
///
/// Logical layout:
/// | M11 M12 M13 |
/// | M21 M22 M23 |
/// | M31 M32 M33 |
[CRepr]
struct Matrix3x3 : IEquatable<Matrix3x3>, IHashable
{
	// Column 0
	public float M11, M21, M31;
	// Column 1
	public float M12, M22, M32;
	// Column 2
	public float M13, M23, M33;

	/// Creates a matrix with all elements set to the specified value.
	public this(float value)
	{
		M11 = M21 = M31 = value;
		M12 = M22 = M32 = value;
		M13 = M23 = M33 = value;
	}

	/// Creates a matrix from individual elements (row-major order for convenience).
	public this(
		float m11, float m12, float m13,
		float m21, float m22, float m23,
		float m31, float m32, float m33)
	{
		M11 = m11; M12 = m12; M13 = m13;
		M21 = m21; M22 = m22; M23 = m23;
		M31 = m31; M32 = m32; M33 = m33;
	}

	/// Creates a matrix from three column vectors.
	public this(Vector3 column0, Vector3 column1, Vector3 column2)
	{
		M11 = column0.X; M21 = column0.Y; M31 = column0.Z;
		M12 = column1.X; M22 = column1.Y; M32 = column1.Z;
		M13 = column2.X; M23 = column2.Y; M33 = column2.Z;
	}

	// ---- Static Properties ----

	/// The identity matrix.
	public static Matrix3x3 Identity => .(
		1, 0, 0,
		0, 1, 0,
		0, 0, 1
	);

	/// A matrix with all elements set to zero.
	public static Matrix3x3 Zero => .(0);

	// ---- Column/Row Access ----

	/// Gets or sets a column of the matrix.
	public Vector3 this[int column]
	{
		get
		{
			switch (column)
			{
			case 0: return .(M11, M21, M31);
			case 1: return .(M12, M22, M32);
			case 2: return .(M13, M23, M33);
			default: Runtime.FatalError("Column index out of range");
			}
		}
		set mut
		{
			switch (column)
			{
			case 0: M11 = value.X; M21 = value.Y; M31 = value.Z;
			case 1: M12 = value.X; M22 = value.Y; M32 = value.Z;
			case 2: M13 = value.X; M23 = value.Y; M33 = value.Z;
			default: Runtime.FatalError("Column index out of range");
			}
		}
	}

	/// Gets column 0.
	public Vector3 Column0 => .(M11, M21, M31);

	/// Gets column 1.
	public Vector3 Column1 => .(M12, M22, M32);

	/// Gets column 2.
	public Vector3 Column2 => .(M13, M23, M33);

	/// Gets row 0.
	public Vector3 Row0 => .(M11, M12, M13);

	/// Gets row 1.
	public Vector3 Row1 => .(M21, M22, M23);

	/// Gets row 2.
	public Vector3 Row2 => .(M31, M32, M33);

	// ---- Properties ----

	/// Gets the determinant of the matrix.
	public float Determinant
	{
		get
		{
			return M11 * (M22 * M33 - M23 * M32)
				 - M12 * (M21 * M33 - M23 * M31)
				 + M13 * (M21 * M32 - M22 * M31);
		}
	}

	/// Gets the transpose of this matrix.
	public Matrix3x3 Transposed => .(
		M11, M21, M31,
		M12, M22, M32,
		M13, M23, M33
	);

	// ---- Operators ----

	public static Matrix3x3 operator +(Matrix3x3 a, Matrix3x3 b)
	{
		return .(
			a.M11 + b.M11, a.M12 + b.M12, a.M13 + b.M13,
			a.M21 + b.M21, a.M22 + b.M22, a.M23 + b.M23,
			a.M31 + b.M31, a.M32 + b.M32, a.M33 + b.M33
		);
	}

	public static Matrix3x3 operator -(Matrix3x3 a, Matrix3x3 b)
	{
		return .(
			a.M11 - b.M11, a.M12 - b.M12, a.M13 - b.M13,
			a.M21 - b.M21, a.M22 - b.M22, a.M23 - b.M23,
			a.M31 - b.M31, a.M32 - b.M32, a.M33 - b.M33
		);
	}

	public static Matrix3x3 operator *(Matrix3x3 a, Matrix3x3 b)
	{
		return .(
			a.M11 * b.M11 + a.M12 * b.M21 + a.M13 * b.M31,
			a.M11 * b.M12 + a.M12 * b.M22 + a.M13 * b.M32,
			a.M11 * b.M13 + a.M12 * b.M23 + a.M13 * b.M33,

			a.M21 * b.M11 + a.M22 * b.M21 + a.M23 * b.M31,
			a.M21 * b.M12 + a.M22 * b.M22 + a.M23 * b.M32,
			a.M21 * b.M13 + a.M22 * b.M23 + a.M23 * b.M33,

			a.M31 * b.M11 + a.M32 * b.M21 + a.M33 * b.M31,
			a.M31 * b.M12 + a.M32 * b.M22 + a.M33 * b.M32,
			a.M31 * b.M13 + a.M32 * b.M23 + a.M33 * b.M33
		);
	}

	public static Matrix3x3 operator *(Matrix3x3 m, float s)
	{
		return .(
			m.M11 * s, m.M12 * s, m.M13 * s,
			m.M21 * s, m.M22 * s, m.M23 * s,
			m.M31 * s, m.M32 * s, m.M33 * s
		);
	}

	public static Matrix3x3 operator *(float s, Matrix3x3 m) => m * s;

	/// Transforms a vector by this matrix.
	public static Vector3 operator *(Matrix3x3 m, Vector3 v)
	{
		return .(
			m.M11 * v.X + m.M12 * v.Y + m.M13 * v.Z,
			m.M21 * v.X + m.M22 * v.Y + m.M23 * v.Z,
			m.M31 * v.X + m.M32 * v.Y + m.M33 * v.Z
		);
	}

	public static Matrix3x3 operator -(Matrix3x3 m)
	{
		return .(
			-m.M11, -m.M12, -m.M13,
			-m.M21, -m.M22, -m.M23,
			-m.M31, -m.M32, -m.M33
		);
	}

	public static bool operator ==(Matrix3x3 a, Matrix3x3 b)
	{
		return a.M11 == b.M11 && a.M12 == b.M12 && a.M13 == b.M13 &&
			   a.M21 == b.M21 && a.M22 == b.M22 && a.M23 == b.M23 &&
			   a.M31 == b.M31 && a.M32 == b.M32 && a.M33 == b.M33;
	}

	public static bool operator !=(Matrix3x3 a, Matrix3x3 b) => !(a == b);

	// ---- Methods ----

	/// Transposes this matrix in place.
	public void Transpose() mut
	{
		Swap!(ref M12, ref M21);
		Swap!(ref M13, ref M31);
		Swap!(ref M23, ref M32);
	}

	/// Inverts this matrix in place. Returns false if the matrix is singular.
	public bool Invert() mut
	{
		let det = Determinant;
		if (Math.Abs(det) < MathUtil.Epsilon)
			return false;

		let invDet = 1.0f / det;

		let m11 = (M22 * M33 - M23 * M32) * invDet;
		let m12 = (M13 * M32 - M12 * M33) * invDet;
		let m13 = (M12 * M23 - M13 * M22) * invDet;
		let m21 = (M23 * M31 - M21 * M33) * invDet;
		let m22 = (M11 * M33 - M13 * M31) * invDet;
		let m23 = (M13 * M21 - M11 * M23) * invDet;
		let m31 = (M21 * M32 - M22 * M31) * invDet;
		let m32 = (M12 * M31 - M11 * M32) * invDet;
		let m33 = (M11 * M22 - M12 * M21) * invDet;

		M11 = m11; M12 = m12; M13 = m13;
		M21 = m21; M22 = m22; M23 = m23;
		M31 = m31; M32 = m32; M33 = m33;
		return true;
	}

	/// Returns the inverse of this matrix, or Identity if singular.
	public Matrix3x3 Inverse()
	{
		var result = this;
		if (!result.Invert())
			return .Identity;
		return result;
	}

	// ---- Factory Methods ----

	/// Creates a rotation matrix around the X axis.
	public static Matrix3x3 CreateRotationX(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			1, 0, 0,
			0, cos, -sin,
			0, sin, cos
		);
	}

	/// Creates a rotation matrix around the Y axis.
	public static Matrix3x3 CreateRotationY(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			cos, 0, sin,
			0, 1, 0,
			-sin, 0, cos
		);
	}

	/// Creates a rotation matrix around the Z axis.
	public static Matrix3x3 CreateRotationZ(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			cos, -sin, 0,
			sin, cos, 0,
			0, 0, 1
		);
	}

	/// Creates a uniform scale matrix.
	public static Matrix3x3 CreateScale(float scale)
	{
		return .(
			scale, 0, 0,
			0, scale, 0,
			0, 0, scale
		);
	}

	/// Creates a non-uniform scale matrix.
	public static Matrix3x3 CreateScale(float x, float y, float z)
	{
		return .(
			x, 0, 0,
			0, y, 0,
			0, 0, z
		);
	}

	/// Creates a scale matrix from a vector.
	public static Matrix3x3 CreateScale(Vector3 scale)
	{
		return CreateScale(scale.X, scale.Y, scale.Z);
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Matrix3x3 other)
	{
		return this == other;
	}

	public int GetHashCode()
	{
		var hash = M11.GetHashCode();
		hash = (hash * 397) ^ M12.GetHashCode();
		hash = (hash * 397) ^ M13.GetHashCode();
		hash = (hash * 397) ^ M21.GetHashCode();
		hash = (hash * 397) ^ M22.GetHashCode();
		hash = (hash * 397) ^ M23.GetHashCode();
		hash = (hash * 397) ^ M31.GetHashCode();
		hash = (hash * 397) ^ M32.GetHashCode();
		hash = (hash * 397) ^ M33.GetHashCode();
		return hash;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF(
			"[({}, {}, {}), ({}, {}, {}), ({}, {}, {})]",
			M11, M12, M13, M21, M22, M23, M31, M32, M33
		);
	}
}
