using System;

namespace Sedulous.Mathematics;

/// A 4x4 matrix stored in column-major order.
///
/// Memory layout (column-major, OpenGL compatible):
/// Column 0: M11, M21, M31, M41
/// Column 1: M12, M22, M32, M42
/// Column 2: M13, M23, M33, M43
/// Column 3: M14, M24, M34, M44
///
/// Logical layout:
/// | M11 M12 M13 M14 |
/// | M21 M22 M23 M24 |
/// | M31 M32 M33 M34 |
/// | M41 M42 M43 M44 |
[CRepr]
struct Matrix4x4 : IEquatable<Matrix4x4>, IHashable
{
	// Column 0
	public float M11, M21, M31, M41;
	// Column 1
	public float M12, M22, M32, M42;
	// Column 2
	public float M13, M23, M33, M43;
	// Column 3
	public float M14, M24, M34, M44;

	/// Creates a matrix with all elements set to the specified value.
	public this(float value)
	{
		M11 = M21 = M31 = M41 = value;
		M12 = M22 = M32 = M42 = value;
		M13 = M23 = M33 = M43 = value;
		M14 = M24 = M34 = M44 = value;
	}

	/// Creates a matrix from individual elements (row-major order for convenience).
	public this(
		float m11, float m12, float m13, float m14,
		float m21, float m22, float m23, float m24,
		float m31, float m32, float m33, float m34,
		float m41, float m42, float m43, float m44)
	{
		M11 = m11; M12 = m12; M13 = m13; M14 = m14;
		M21 = m21; M22 = m22; M23 = m23; M24 = m24;
		M31 = m31; M32 = m32; M33 = m33; M34 = m34;
		M41 = m41; M42 = m42; M43 = m43; M44 = m44;
	}

	/// Creates a matrix from four column vectors.
	public this(Vector4 column0, Vector4 column1, Vector4 column2, Vector4 column3)
	{
		M11 = column0.X; M21 = column0.Y; M31 = column0.Z; M41 = column0.W;
		M12 = column1.X; M22 = column1.Y; M32 = column1.Z; M42 = column1.W;
		M13 = column2.X; M23 = column2.Y; M33 = column2.Z; M43 = column2.W;
		M14 = column3.X; M24 = column3.Y; M34 = column3.Z; M44 = column3.W;
	}

	// ---- Static Properties ----

	/// The identity matrix.
	public static Matrix4x4 Identity => .(
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1
	);

	/// A matrix with all elements set to zero.
	public static Matrix4x4 Zero => .(0);

	// ---- Column/Row Access ----

	/// Gets or sets a column of the matrix.
	public Vector4 this[int column]
	{
		get
		{
			switch (column)
			{
			case 0: return .(M11, M21, M31, M41);
			case 1: return .(M12, M22, M32, M42);
			case 2: return .(M13, M23, M33, M43);
			case 3: return .(M14, M24, M34, M44);
			default: Runtime.FatalError("Column index out of range");
			}
		}
		set mut
		{
			switch (column)
			{
			case 0: M11 = value.X; M21 = value.Y; M31 = value.Z; M41 = value.W;
			case 1: M12 = value.X; M22 = value.Y; M32 = value.Z; M42 = value.W;
			case 2: M13 = value.X; M23 = value.Y; M33 = value.Z; M43 = value.W;
			case 3: M14 = value.X; M24 = value.Y; M34 = value.Z; M44 = value.W;
			default: Runtime.FatalError("Column index out of range");
			}
		}
	}

	/// Gets column 0.
	public Vector4 Column0 => .(M11, M21, M31, M41);

	/// Gets column 1.
	public Vector4 Column1 => .(M12, M22, M32, M42);

	/// Gets column 2.
	public Vector4 Column2 => .(M13, M23, M33, M43);

	/// Gets column 3.
	public Vector4 Column3 => .(M14, M24, M34, M44);

	/// Gets row 0.
	public Vector4 Row0 => .(M11, M12, M13, M14);

	/// Gets row 1.
	public Vector4 Row1 => .(M21, M22, M23, M24);

	/// Gets row 2.
	public Vector4 Row2 => .(M31, M32, M33, M34);

	/// Gets row 3.
	public Vector4 Row3 => .(M41, M42, M43, M44);

	// ---- Properties ----

	/// Gets the translation component of the matrix.
	public Vector3 Translation => .(M14, M24, M34);

	/// Gets the upper-left 3x3 portion of this matrix.
	public Matrix3x3 Upper3x3 => .(
		M11, M12, M13,
		M21, M22, M23,
		M31, M32, M33
	);

	/// Gets the determinant of the matrix.
	public float Determinant
	{
		get
		{
			// Using cofactor expansion along the first row
			let a = M11 * (M22 * (M33 * M44 - M34 * M43) - M23 * (M32 * M44 - M34 * M42) + M24 * (M32 * M43 - M33 * M42));
			let b = M12 * (M21 * (M33 * M44 - M34 * M43) - M23 * (M31 * M44 - M34 * M41) + M24 * (M31 * M43 - M33 * M41));
			let c = M13 * (M21 * (M32 * M44 - M34 * M42) - M22 * (M31 * M44 - M34 * M41) + M24 * (M31 * M42 - M32 * M41));
			let d = M14 * (M21 * (M32 * M43 - M33 * M42) - M22 * (M31 * M43 - M33 * M41) + M23 * (M31 * M42 - M32 * M41));
			return a - b + c - d;
		}
	}

	/// Gets the transpose of this matrix.
	public Matrix4x4 Transposed => .(
		M11, M21, M31, M41,
		M12, M22, M32, M42,
		M13, M23, M33, M43,
		M14, M24, M34, M44
	);

	// ---- Operators ----

	public static Matrix4x4 operator +(Matrix4x4 a, Matrix4x4 b)
	{
		return .(
			a.M11 + b.M11, a.M12 + b.M12, a.M13 + b.M13, a.M14 + b.M14,
			a.M21 + b.M21, a.M22 + b.M22, a.M23 + b.M23, a.M24 + b.M24,
			a.M31 + b.M31, a.M32 + b.M32, a.M33 + b.M33, a.M34 + b.M34,
			a.M41 + b.M41, a.M42 + b.M42, a.M43 + b.M43, a.M44 + b.M44
		);
	}

	public static Matrix4x4 operator -(Matrix4x4 a, Matrix4x4 b)
	{
		return .(
			a.M11 - b.M11, a.M12 - b.M12, a.M13 - b.M13, a.M14 - b.M14,
			a.M21 - b.M21, a.M22 - b.M22, a.M23 - b.M23, a.M24 - b.M24,
			a.M31 - b.M31, a.M32 - b.M32, a.M33 - b.M33, a.M34 - b.M34,
			a.M41 - b.M41, a.M42 - b.M42, a.M43 - b.M43, a.M44 - b.M44
		);
	}

	public static Matrix4x4 operator *(Matrix4x4 a, Matrix4x4 b)
	{
		return .(
			// Row 0
			a.M11 * b.M11 + a.M12 * b.M21 + a.M13 * b.M31 + a.M14 * b.M41,
			a.M11 * b.M12 + a.M12 * b.M22 + a.M13 * b.M32 + a.M14 * b.M42,
			a.M11 * b.M13 + a.M12 * b.M23 + a.M13 * b.M33 + a.M14 * b.M43,
			a.M11 * b.M14 + a.M12 * b.M24 + a.M13 * b.M34 + a.M14 * b.M44,
			// Row 1
			a.M21 * b.M11 + a.M22 * b.M21 + a.M23 * b.M31 + a.M24 * b.M41,
			a.M21 * b.M12 + a.M22 * b.M22 + a.M23 * b.M32 + a.M24 * b.M42,
			a.M21 * b.M13 + a.M22 * b.M23 + a.M23 * b.M33 + a.M24 * b.M43,
			a.M21 * b.M14 + a.M22 * b.M24 + a.M23 * b.M34 + a.M24 * b.M44,
			// Row 2
			a.M31 * b.M11 + a.M32 * b.M21 + a.M33 * b.M31 + a.M34 * b.M41,
			a.M31 * b.M12 + a.M32 * b.M22 + a.M33 * b.M32 + a.M34 * b.M42,
			a.M31 * b.M13 + a.M32 * b.M23 + a.M33 * b.M33 + a.M34 * b.M43,
			a.M31 * b.M14 + a.M32 * b.M24 + a.M33 * b.M34 + a.M34 * b.M44,
			// Row 3
			a.M41 * b.M11 + a.M42 * b.M21 + a.M43 * b.M31 + a.M44 * b.M41,
			a.M41 * b.M12 + a.M42 * b.M22 + a.M43 * b.M32 + a.M44 * b.M42,
			a.M41 * b.M13 + a.M42 * b.M23 + a.M43 * b.M33 + a.M44 * b.M43,
			a.M41 * b.M14 + a.M42 * b.M24 + a.M43 * b.M34 + a.M44 * b.M44
		);
	}

	public static Matrix4x4 operator *(Matrix4x4 m, float s)
	{
		return .(
			m.M11 * s, m.M12 * s, m.M13 * s, m.M14 * s,
			m.M21 * s, m.M22 * s, m.M23 * s, m.M24 * s,
			m.M31 * s, m.M32 * s, m.M33 * s, m.M34 * s,
			m.M41 * s, m.M42 * s, m.M43 * s, m.M44 * s
		);
	}

	public static Matrix4x4 operator *(float s, Matrix4x4 m) => m * s;

	/// Transforms a Vector4 by this matrix.
	public static Vector4 operator *(Matrix4x4 m, Vector4 v)
	{
		return .(
			m.M11 * v.X + m.M12 * v.Y + m.M13 * v.Z + m.M14 * v.W,
			m.M21 * v.X + m.M22 * v.Y + m.M23 * v.Z + m.M24 * v.W,
			m.M31 * v.X + m.M32 * v.Y + m.M33 * v.Z + m.M34 * v.W,
			m.M41 * v.X + m.M42 * v.Y + m.M43 * v.Z + m.M44 * v.W
		);
	}

	public static Matrix4x4 operator -(Matrix4x4 m)
	{
		return .(
			-m.M11, -m.M12, -m.M13, -m.M14,
			-m.M21, -m.M22, -m.M23, -m.M24,
			-m.M31, -m.M32, -m.M33, -m.M34,
			-m.M41, -m.M42, -m.M43, -m.M44
		);
	}

	public static bool operator ==(Matrix4x4 a, Matrix4x4 b)
	{
		return a.M11 == b.M11 && a.M12 == b.M12 && a.M13 == b.M13 && a.M14 == b.M14 &&
			   a.M21 == b.M21 && a.M22 == b.M22 && a.M23 == b.M23 && a.M24 == b.M24 &&
			   a.M31 == b.M31 && a.M32 == b.M32 && a.M33 == b.M33 && a.M34 == b.M34 &&
			   a.M41 == b.M41 && a.M42 == b.M42 && a.M43 == b.M43 && a.M44 == b.M44;
	}

	public static bool operator !=(Matrix4x4 a, Matrix4x4 b) => !(a == b);

	// ---- Methods ----

	/// Transposes this matrix in place.
	public void Transpose() mut
	{
		Swap!(ref M12, ref M21);
		Swap!(ref M13, ref M31);
		Swap!(ref M14, ref M41);
		Swap!(ref M23, ref M32);
		Swap!(ref M24, ref M42);
		Swap!(ref M34, ref M43);
	}

	/// Transforms a Vector3 as a point (w=1).
	public Vector3 TransformPoint(Vector3 point)
	{
		let w = M41 * point.X + M42 * point.Y + M43 * point.Z + M44;
		return .(
			(M11 * point.X + M12 * point.Y + M13 * point.Z + M14) / w,
			(M21 * point.X + M22 * point.Y + M23 * point.Z + M24) / w,
			(M31 * point.X + M32 * point.Y + M33 * point.Z + M34) / w
		);
	}

	/// Transforms a Vector3 as a direction (w=0).
	public Vector3 TransformDirection(Vector3 direction)
	{
		return .(
			M11 * direction.X + M12 * direction.Y + M13 * direction.Z,
			M21 * direction.X + M22 * direction.Y + M23 * direction.Z,
			M31 * direction.X + M32 * direction.Y + M33 * direction.Z
		);
	}

	/// Inverts this matrix in place. Returns false if the matrix is singular.
	public bool Invert() mut
	{
		let det = Determinant;
		if (Math.Abs(det) < MathUtil.Epsilon)
			return false;

		let invDet = 1.0f / det;

		// Calculate cofactor matrix, transpose it, and divide by determinant
		let m11 = (M22 * (M33 * M44 - M34 * M43) - M23 * (M32 * M44 - M34 * M42) + M24 * (M32 * M43 - M33 * M42)) * invDet;
		let m12 = -(M12 * (M33 * M44 - M34 * M43) - M13 * (M32 * M44 - M34 * M42) + M14 * (M32 * M43 - M33 * M42)) * invDet;
		let m13 = (M12 * (M23 * M44 - M24 * M43) - M13 * (M22 * M44 - M24 * M42) + M14 * (M22 * M43 - M23 * M42)) * invDet;
		let m14 = -(M12 * (M23 * M34 - M24 * M33) - M13 * (M22 * M34 - M24 * M32) + M14 * (M22 * M33 - M23 * M32)) * invDet;

		let m21 = -(M21 * (M33 * M44 - M34 * M43) - M23 * (M31 * M44 - M34 * M41) + M24 * (M31 * M43 - M33 * M41)) * invDet;
		let m22 = (M11 * (M33 * M44 - M34 * M43) - M13 * (M31 * M44 - M34 * M41) + M14 * (M31 * M43 - M33 * M41)) * invDet;
		let m23 = -(M11 * (M23 * M44 - M24 * M43) - M13 * (M21 * M44 - M24 * M41) + M14 * (M21 * M43 - M23 * M41)) * invDet;
		let m24 = (M11 * (M23 * M34 - M24 * M33) - M13 * (M21 * M34 - M24 * M31) + M14 * (M21 * M33 - M23 * M31)) * invDet;

		let m31 = (M21 * (M32 * M44 - M34 * M42) - M22 * (M31 * M44 - M34 * M41) + M24 * (M31 * M42 - M32 * M41)) * invDet;
		let m32 = -(M11 * (M32 * M44 - M34 * M42) - M12 * (M31 * M44 - M34 * M41) + M14 * (M31 * M42 - M32 * M41)) * invDet;
		let m33 = (M11 * (M22 * M44 - M24 * M42) - M12 * (M21 * M44 - M24 * M41) + M14 * (M21 * M42 - M22 * M41)) * invDet;
		let m34 = -(M11 * (M22 * M34 - M24 * M32) - M12 * (M21 * M34 - M24 * M31) + M14 * (M21 * M32 - M22 * M31)) * invDet;

		let m41 = -(M21 * (M32 * M43 - M33 * M42) - M22 * (M31 * M43 - M33 * M41) + M23 * (M31 * M42 - M32 * M41)) * invDet;
		let m42 = (M11 * (M32 * M43 - M33 * M42) - M12 * (M31 * M43 - M33 * M41) + M13 * (M31 * M42 - M32 * M41)) * invDet;
		let m43 = -(M11 * (M22 * M43 - M23 * M42) - M12 * (M21 * M43 - M23 * M41) + M13 * (M21 * M42 - M22 * M41)) * invDet;
		let m44 = (M11 * (M22 * M33 - M23 * M32) - M12 * (M21 * M33 - M23 * M31) + M13 * (M21 * M32 - M22 * M31)) * invDet;

		M11 = m11; M12 = m12; M13 = m13; M14 = m14;
		M21 = m21; M22 = m22; M23 = m23; M24 = m24;
		M31 = m31; M32 = m32; M33 = m33; M34 = m34;
		M41 = m41; M42 = m42; M43 = m43; M44 = m44;
		return true;
	}

	/// Returns the inverse of this matrix, or Identity if singular.
	public Matrix4x4 Inverse()
	{
		var result = this;
		if (!result.Invert())
			return .Identity;
		return result;
	}

	// ---- Factory Methods ----

	/// Creates a translation matrix.
	public static Matrix4x4 CreateTranslation(float x, float y, float z)
	{
		return .(
			1, 0, 0, x,
			0, 1, 0, y,
			0, 0, 1, z,
			0, 0, 0, 1
		);
	}

	/// Creates a translation matrix from a vector.
	public static Matrix4x4 CreateTranslation(Vector3 position)
	{
		return CreateTranslation(position.X, position.Y, position.Z);
	}

	/// Creates a rotation matrix around the X axis.
	public static Matrix4x4 CreateRotationX(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			1, 0, 0, 0,
			0, cos, -sin, 0,
			0, sin, cos, 0,
			0, 0, 0, 1
		);
	}

	/// Creates a rotation matrix around the Y axis.
	public static Matrix4x4 CreateRotationY(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			cos, 0, sin, 0,
			0, 1, 0, 0,
			-sin, 0, cos, 0,
			0, 0, 0, 1
		);
	}

	/// Creates a rotation matrix around the Z axis.
	public static Matrix4x4 CreateRotationZ(float radians)
	{
		let cos = Math.Cos(radians);
		let sin = Math.Sin(radians);
		return .(
			cos, -sin, 0, 0,
			sin, cos, 0, 0,
			0, 0, 1, 0,
			0, 0, 0, 1
		);
	}

	/// Creates a uniform scale matrix.
	public static Matrix4x4 CreateScale(float scale)
	{
		return .(
			scale, 0, 0, 0,
			0, scale, 0, 0,
			0, 0, scale, 0,
			0, 0, 0, 1
		);
	}

	/// Creates a non-uniform scale matrix.
	public static Matrix4x4 CreateScale(float x, float y, float z)
	{
		return .(
			x, 0, 0, 0,
			0, y, 0, 0,
			0, 0, z, 0,
			0, 0, 0, 1
		);
	}

	/// Creates a scale matrix from a vector.
	public static Matrix4x4 CreateScale(Vector3 scale)
	{
		return CreateScale(scale.X, scale.Y, scale.Z);
	}

	/// Creates a perspective projection matrix (OpenGL style, Z maps to [-1, 1]).
	public static Matrix4x4 CreatePerspective(float fovY, float aspectRatio, float nearPlane, float farPlane)
	{
		let tanHalfFov = Math.Tan(fovY * 0.5f);
		let range = farPlane - nearPlane;

		return .(
			1.0f / (aspectRatio * tanHalfFov), 0, 0, 0,
			0, 1.0f / tanHalfFov, 0, 0,
			0, 0, -(farPlane + nearPlane) / range, -2.0f * farPlane * nearPlane / range,
			0, 0, -1, 0
		);
	}

	/// Creates a perspective projection matrix for Vulkan (Z maps to [0, 1]).
	public static Matrix4x4 CreatePerspectiveVulkan(float fovY, float aspectRatio, float nearPlane, float farPlane)
	{
		let tanHalfFov = Math.Tan(fovY * 0.5f);
		let range = farPlane - nearPlane;

		return .(
			1.0f / (aspectRatio * tanHalfFov), 0, 0, 0,
			0, 1.0f / tanHalfFov, 0, 0,
			0, 0, -farPlane / range, -(farPlane * nearPlane) / range,
			0, 0, -1, 0
		);
	}

	/// Creates an orthographic projection matrix.
	public static Matrix4x4 CreateOrthographic(float width, float height, float nearPlane, float farPlane)
	{
		let range = farPlane - nearPlane;

		return .(
			2.0f / width, 0, 0, 0,
			0, 2.0f / height, 0, 0,
			0, 0, -2.0f / range, -(farPlane + nearPlane) / range,
			0, 0, 0, 1
		);
	}

	/// Creates an orthographic off-center projection matrix (OpenGL style, Z maps to [-1, 1]).
	public static Matrix4x4 CreateOrthographicOffCenter(float left, float right, float bottom, float top, float nearPlane, float farPlane)
	{
		let width = right - left;
		let height = top - bottom;
		let depth = farPlane - nearPlane;

		return .(
			2.0f / width, 0, 0, -(right + left) / width,
			0, 2.0f / height, 0, -(top + bottom) / height,
			0, 0, -2.0f / depth, -(farPlane + nearPlane) / depth,
			0, 0, 0, 1
		);
	}

	/// Creates an orthographic off-center projection matrix for Vulkan (Z maps to [0, 1]).
	public static Matrix4x4 CreateOrthographicOffCenterVulkan(float left, float right, float bottom, float top, float nearPlane, float farPlane)
	{
		let width = right - left;
		let height = top - bottom;
		let depth = farPlane - nearPlane;

		return .(
			2.0f / width, 0, 0, -(right + left) / width,
			0, 2.0f / height, 0, -(top + bottom) / height,
			0, 0, -1.0f / depth, -nearPlane / depth,
			0, 0, 0, 1
		);
	}

	/// Creates a view matrix looking at a target.
	public static Matrix4x4 CreateLookAt(Vector3 eye, Vector3 target, Vector3 up)
	{
		let zAxis = (eye - target).Normalized; // Forward (camera looks down -Z)
		let xAxis = Vector3.Cross(up, zAxis).Normalized; // Right
		let yAxis = Vector3.Cross(zAxis, xAxis); // Up

		return .(
			xAxis.X, xAxis.Y, xAxis.Z, -Vector3.Dot(xAxis, eye),
			yAxis.X, yAxis.Y, yAxis.Z, -Vector3.Dot(yAxis, eye),
			zAxis.X, zAxis.Y, zAxis.Z, -Vector3.Dot(zAxis, eye),
			0, 0, 0, 1
		);
	}

	/// Creates a matrix from translation, rotation, and scale.
	public static Matrix4x4 CreateTRS(Vector3 translation, Matrix3x3 rotation, Vector3 scale)
	{
		return .(
			rotation.M11 * scale.X, rotation.M12 * scale.Y, rotation.M13 * scale.Z, translation.X,
			rotation.M21 * scale.X, rotation.M22 * scale.Y, rotation.M23 * scale.Z, translation.Y,
			rotation.M31 * scale.X, rotation.M32 * scale.Y, rotation.M33 * scale.Z, translation.Z,
			0, 0, 0, 1
		);
	}

	/// Creates a rotation matrix from a quaternion.
	public static Matrix4x4 CreateFromQuaternion(Quaternion q)
	{
		float xx = q.X * q.X;
		float yy = q.Y * q.Y;
		float zz = q.Z * q.Z;
		float xy = q.X * q.Y;
		float xz = q.X * q.Z;
		float yz = q.Y * q.Z;
		float wx = q.W * q.X;
		float wy = q.W * q.Y;
		float wz = q.W * q.Z;

		return .(
			1.0f - 2.0f * (yy + zz), 2.0f * (xy - wz), 2.0f * (xz + wy), 0,
			2.0f * (xy + wz), 1.0f - 2.0f * (xx + zz), 2.0f * (yz - wx), 0,
			2.0f * (xz - wy), 2.0f * (yz + wx), 1.0f - 2.0f * (xx + yy), 0,
			0, 0, 0, 1
		);
	}

	// ---- IEquatable / IHashable ----

	public bool Equals(Matrix4x4 other)
	{
		return this == other;
	}

	public int GetHashCode()
	{
		var hash = M11.GetHashCode();
		hash = (hash * 397) ^ M12.GetHashCode();
		hash = (hash * 397) ^ M13.GetHashCode();
		hash = (hash * 397) ^ M14.GetHashCode();
		hash = (hash * 397) ^ M21.GetHashCode();
		hash = (hash * 397) ^ M22.GetHashCode();
		hash = (hash * 397) ^ M23.GetHashCode();
		hash = (hash * 397) ^ M24.GetHashCode();
		hash = (hash * 397) ^ M31.GetHashCode();
		hash = (hash * 397) ^ M32.GetHashCode();
		hash = (hash * 397) ^ M33.GetHashCode();
		hash = (hash * 397) ^ M34.GetHashCode();
		hash = (hash * 397) ^ M41.GetHashCode();
		hash = (hash * 397) ^ M42.GetHashCode();
		hash = (hash * 397) ^ M43.GetHashCode();
		hash = (hash * 397) ^ M44.GetHashCode();
		return hash;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF(
			"[({}, {}, {}, {}), ({}, {}, {}, {}), ({}, {}, {}, {}), ({}, {}, {}, {})]",
			M11, M12, M13, M14, M21, M22, M23, M24, M31, M32, M33, M34, M41, M42, M43, M44
		);
	}
}
