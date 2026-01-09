# Sedulous.Mathematics

A comprehensive mathematical library providing vectors, matrices, quaternions, colors, and geometric primitives for 3D graphics and game development.

## Overview

The library uses **row-major matrices** (DirectX/XNA convention) and a **right-handed coordinate system** where:
- +X = Right
- +Y = Up
- -Z = Forward

## Core Types

### Vectors

| Type | Components | Size | Purpose |
|------|------------|------|---------|
| `Vector2` | X, Y | 8 bytes | 2D positions, UVs |
| `Vector3` | X, Y, Z | 12 bytes | 3D positions, directions |
| `Vector4` | X, Y, Z, W | 16 bytes | Homogeneous coords, colors |

### Points (Integer and Float)

| Type | Components | Purpose |
|------|------------|---------|
| `Point2` | X, Y (int32) | Pixel coordinates |
| `Point2F` | X, Y (float) | Sub-pixel positions |
| `Point2D` | X, Y (double) | High precision |

### Sizes

| Type | Components | Purpose |
|------|------------|---------|
| `Size2` | Width, Height (int32) | Dimensions |
| `Size2F` | Width, Height (float) | Float dimensions |
| `Size2D` | Width, Height (double) | High precision |
| `Size3` | Width, Height, Depth | 3D dimensions |
| `Size3F`, `Size3D` | Float/double variants | 3D dimensions |

### Rectangles

| Type | Components | Purpose |
|------|------------|---------|
| `Rectangle` | X, Y, Width, Height (int32) | Pixel regions |
| `RectangleF` | X, Y, Width, Height (float) | Float regions |
| `RectangleD` | X, Y, Width, Height (double) | High precision |

### Transforms

| Type | Size | Purpose |
|------|------|---------|
| `Matrix` | 64 bytes (4x4 float) | Transformations |
| `Quaternion` | 16 bytes (x, y, z, w) | Rotations |
| `Radians` | 4 bytes | Angle wrapper |

### Geometry

| Type | Purpose |
|------|---------|
| `Plane` | Normal + distance |
| `Ray` | Position + direction |
| `BoundingBox` | Axis-aligned min/max |
| `BoundingSphere` | Center + radius |
| `BoundingFrustum` | Camera frustum |
| `Circle`, `CircleF`, `CircleD` | 2D circles |

### Color

| Type | Format | Purpose |
|------|--------|---------|
| `Color` | ABGR packed uint32 | RGBA color |

## Vector Operations

### Arithmetic

```beef
Vector3 a = .(1, 2, 3);
Vector3 b = .(4, 5, 6);

Vector3 sum = a + b;          // (5, 7, 9)
Vector3 diff = a - b;         // (-3, -3, -3)
Vector3 scaled = a * 2.0f;    // (2, 4, 6)
Vector3 divided = a / 2.0f;   // (0.5, 1, 1.5)
Vector3 negated = -a;         // (-1, -2, -3)
Vector3 product = a * b;      // Element-wise: (4, 10, 18)
```

### Static Methods

```beef
// Dot and cross products
float dot = Vector3.Dot(a, b);
Vector3 cross = Vector3.Cross(a, b);

// Length and distance
float len = a.Length();
float lenSq = a.LengthSquared();
float dist = Vector3.Distance(a, b);
float distSq = Vector3.DistanceSquared(a, b);

// Normalization
Vector3 normalized = Vector3.Normalize(a);

// Clamping
Vector3 clamped = Vector3.Clamp(value, min, max);
Vector3 minV = Vector3.Min(a, b);
Vector3 maxV = Vector3.Max(a, b);

// Reflection
Vector3 reflected = Vector3.Reflect(incident, normal);
```

### Interpolation

```beef
// Linear interpolation
Vector3 lerped = Vector3.Lerp(a, b, 0.5f);

// Smooth interpolation (ease in/out)
Vector3 smooth = Vector3.SmoothStep(a, b, t);

// Hermite spline
Vector3 hermite = Vector3.Hermite(p1, t1, p2, t2, t);

// Catmull-Rom spline
Vector3 catmull = Vector3.CatmullRom(p1, p2, p3, p4, t);

// Barycentric coordinates
Vector3 bary = Vector3.Barycentric(v1, v2, v3, b2, b3);
```

### Transforms

```beef
// Transform by matrix
Vector3 transformed = Vector3.Transform(position, matrix);

// Transform normal (no translation)
Vector3 normal = Vector3.TransformNormal(direction, matrix);

// Transform by quaternion
Vector3 rotated = Vector3.Transform(vector, quaternion);
```

### Direction Constants (Vector3)

```beef
Vector3.Zero     // (0, 0, 0)
Vector3.One      // (1, 1, 1)
Vector3.UnitX    // (1, 0, 0)
Vector3.UnitY    // (0, 1, 0)
Vector3.UnitZ    // (0, 0, 1)

// Right-handed coordinate system
Vector3.Right    // (1, 0, 0)   +X
Vector3.Left     // (-1, 0, 0)  -X
Vector3.Up       // (0, 1, 0)   +Y
Vector3.Down     // (0, -1, 0)  -Y
Vector3.Forward  // (0, 0, -1)  -Z
Vector3.Backward // (0, 0, 1)   +Z
```

## Matrix Operations

### Construction

```beef
// Identity
Matrix identity = Matrix.Identity;

// From components
Matrix m = Matrix(
    m11, m12, m13, m14,
    m21, m22, m23, m24,
    m31, m32, m33, m34,
    m41, m42, m43, m44
);
```

### Creation Methods

```beef
// Translation
Matrix translation = Matrix.CreateTranslation(x, y, z);
Matrix translation = Matrix.CreateTranslation(Vector3(x, y, z));

// Scale
Matrix scale = Matrix.CreateScale(uniformScale);
Matrix scale = Matrix.CreateScale(scaleX, scaleY, scaleZ);

// Rotation
Matrix rotX = Matrix.CreateRotationX(radians);
Matrix rotY = Matrix.CreateRotationY(radians);
Matrix rotZ = Matrix.CreateRotationZ(radians);
Matrix rot = Matrix.CreateFromQuaternion(quaternion);
Matrix rot = Matrix.CreateFromAxisAngle(axis, angle);
Matrix rot = Matrix.CreateFromYawPitchRoll(yaw, pitch, roll);

// Look-at (view matrix)
Matrix view = Matrix.CreateLookAt(cameraPos, target, up);

// Perspective projection
Matrix proj = Matrix.CreatePerspectiveFieldOfView(fov, aspect, near, far);

// Orthographic projection
Matrix ortho = Matrix.CreateOrthographic(width, height, near, far);
Matrix ortho = Matrix.CreateOrthographicOffCenter(left, right, bottom, top, near, far);
```

### Operations

```beef
// Multiplication (combines transforms)
Matrix combined = world * view * projection;

// Inverse
Matrix inverse = Matrix.Invert(matrix);

// Transpose
Matrix transposed = Matrix.Transpose(matrix);

// Decompose
Vector3 scale, translation;
Quaternion rotation;
matrix.Decompose(out scale, out rotation, out translation);
```

### Memory Layout

The library uses **row-major** layout (DirectX/XNA convention):

```beef
// Matrix layout:
// | M11 M12 M13 M14 |   Row 1: Right vector (+ scale X)
// | M21 M22 M23 M24 |   Row 2: Up vector (+ scale Y)
// | M31 M32 M33 M34 |   Row 3: Forward vector (+ scale Z)
// | M41 M42 M43 M44 |   Row 4: Translation (X, Y, Z, 1)

// Transform: result = vector * matrix (row vector on left)
// Multiplication order: World * View * Projection
```

## Quaternion Operations

### Construction

```beef
Quaternion identity = Quaternion.Identity;  // (0, 0, 0, 1)

// From axis-angle
Quaternion rot = Quaternion.CreateFromAxisAngle(axis, radians);

// From Euler angles
Quaternion rot = Quaternion.CreateFromYawPitchRoll(yaw, pitch, roll);

// From rotation matrix
Quaternion rot = Quaternion.CreateFromRotationMatrix(matrix);
```

### Operations

```beef
// Multiplication (combines rotations)
Quaternion combined = q1 * q2;  // Applies q2 then q1

// Conjugate (inverse for unit quaternions)
Quaternion conj = Quaternion.Conjugate(q);

// Normalize
Quaternion normalized = Quaternion.Normalize(q);

// Inverse
Quaternion inverse = Quaternion.Inverse(q);

// Interpolation (SLERP)
Quaternion lerped = Quaternion.Slerp(q1, q2, t);
Quaternion lerped = Quaternion.Lerp(q1, q2, t);  // Faster, less accurate

// Transform vector
Vector3 rotated = Vector3.Transform(vector, quaternion);
```

### Convention

```beef
// w = cos(theta/2) for rotation by theta around axis (x, y, z)
// Unit quaternion: x² + y² + z² + w² = 1
```

## Color

### Construction

```beef
// From packed value (ABGR format)
Color c = Color(0xFF0000FF);  // Red

// From floats [0, 1]
Color c = Color(1.0f, 0.0f, 0.0f);       // Red, alpha = 1
Color c = Color(1.0f, 0.0f, 0.0f, 1.0f); // Red with alpha

// From bytes [0, 255]
Color c = Color(255, 0, 0);       // Red, alpha = 255
Color c = Color(255, 0, 0, 255);  // Red with alpha
```

### Predefined Colors

```beef
Color.White        // (255, 255, 255, 255)
Color.Black        // (0, 0, 0, 255)
Color.Red          // (255, 0, 0, 255)
Color.Green        // (0, 255, 0, 255)
Color.Blue         // (0, 0, 255, 255)
Color.Yellow       // (255, 255, 0, 255)
Color.Cyan         // (0, 255, 255, 255)
Color.Magenta      // (255, 0, 255, 255)
Color.Transparent  // (0, 0, 0, 0)
// ... and many more
```

### Properties

```beef
uint8 r = color.R;
uint8 g = color.G;
uint8 b = color.B;
uint8 a = color.A;
uint32 packed = color.PackedValue;  // ABGR format
```

## Rectangle

### Construction

```beef
Rectangle rect = Rectangle(x, y, width, height);
Rectangle rect = Rectangle(position, size);
RectangleF rect = RectangleF(10.0f, 20.0f, 100.0f, 50.0f);
```

### Properties and Methods

```beef
int x = rect.X;
int y = rect.Y;
int width = rect.Width;
int height = rect.Height;

int left = rect.Left;
int right = rect.Right;
int top = rect.Top;
int bottom = rect.Bottom;

Point2 center = rect.Center;
Point2 location = rect.Location;
Size2 size = rect.Size;

bool empty = rect.IsEmpty;
```

### Operations

```beef
// Offset
Rectangle moved = rect + Point2(10, 20);

// Contains
bool contains = rect.Contains(point);
bool contains = rect.Contains(x, y);
bool contains = rect.Contains(otherRect);

// Intersection
bool intersects = rect.Intersects(other);
Rectangle intersection = Rectangle.Intersect(rect1, rect2);

// Union
Rectangle union = Rectangle.Union(rect1, rect2);

// Inflation
rect.Inflate(horizontal, vertical);
```

## Bounding Volumes

### BoundingBox

```beef
BoundingBox box = BoundingBox(min, max);

// From points
BoundingBox box = BoundingBox.CreateFromPoints(points);

// From sphere
BoundingBox box = BoundingBox.CreateFromSphere(sphere);

// Merge
BoundingBox merged = BoundingBox.CreateMerged(box1, box2);

// Containment
ContainmentType result = box.Contains(point);
ContainmentType result = box.Contains(otherBox);
ContainmentType result = box.Contains(sphere);

// Intersection
bool intersects = box.Intersects(otherBox);
bool intersects = box.Intersects(sphere);
float? distance = box.Intersects(ray);
```

### BoundingSphere

```beef
BoundingSphere sphere = BoundingSphere(center, radius);

// From points
BoundingSphere sphere = BoundingSphere.CreateFromPoints(points);

// From bounding box
BoundingSphere sphere = BoundingSphere.CreateFromBoundingBox(box);

// Merge
BoundingSphere merged = BoundingSphere.CreateMerged(s1, s2);

// Containment and intersection
ContainmentType result = sphere.Contains(point);
bool intersects = sphere.Intersects(otherSphere);
float? distance = sphere.Intersects(ray);
```

### BoundingFrustum

```beef
BoundingFrustum frustum = BoundingFrustum(viewProjectionMatrix);

// Get planes
Plane near = frustum.Near;
Plane far = frustum.Far;
Plane left = frustum.Left;
Plane right = frustum.Right;
Plane top = frustum.Top;
Plane bottom = frustum.Bottom;

// Containment (for culling)
ContainmentType result = frustum.Contains(point);
ContainmentType result = frustum.Contains(box);
ContainmentType result = frustum.Contains(sphere);
```

## Ray and Plane

### Ray

```beef
Ray ray = Ray(origin, direction);

// Intersection tests
float? dist = ray.Intersects(plane);
float? dist = ray.Intersects(box);
float? dist = ray.Intersects(sphere);

// Get point along ray
Vector3 point = ray.Position + ray.Direction * distance;
```

### Plane

```beef
Plane plane = Plane(normal, distance);
Plane plane = Plane(a, b, c, d);  // ax + by + cz + d = 0
Plane plane = Plane(point1, point2, point3);  // From 3 points

// Normalize
Plane normalized = Plane.Normalize(plane);

// Dot products
float dot = Plane.Dot(plane, vector4);
float dotCoord = Plane.DotCoordinate(plane, point);
float dotNormal = Plane.DotNormal(plane, normal);

// Classification
PlaneIntersectionType result = plane.Intersects(box);
PlaneIntersectionType result = plane.Intersects(sphere);
```

## MathUtil

### Constants

```beef
float MathUtil.Pi          // 3.14159...
float MathUtil.PiOver2     // Pi / 2
float MathUtil.PiOver4     // Pi / 4
float MathUtil.TwoPi       // Pi * 2
float MathUtil.E           // 2.71828...
```

### Angle Conversion

```beef
float radians = MathUtil.ToRadians(degrees);
float degrees = MathUtil.ToDegrees(radians);
```

### Comparison

```beef
bool equal = MathUtil.AreApproximatelyEqual(a, b);
bool equal = MathUtil.AreApproximatelyEqual(a, b, epsilon);
bool zero = MathUtil.IsApproximatelyZero(value);
bool zero = MathUtil.IsApproximatelyZero(value, epsilon);
```

### Clamping and Interpolation

```beef
float clamped = MathUtil.Clamp(value, min, max);
float lerped = MathUtil.Lerp(a, b, t);
float smoothed = MathUtil.SmoothStep(edge0, edge1, x);
```

## Interpolation Interface

All vector and quaternion types implement `IInterpolatable<T>`:

```beef
interface IInterpolatable<T>
{
    T Interpolate(T target, float t);
}

// Usage
Vector3 result = position.Interpolate(targetPosition, deltaTime);
Quaternion result = rotation.Interpolate(targetRotation, deltaTime);
```

This integrates with the Tweening system for animation.

## Performance Notes

### Dual Method Pattern

Many operations have two forms:

```beef
// Returns result (convenience)
Vector3 result = Vector3.Add(a, b);

// Out parameter (avoids allocation)
Vector3.Add(in a, in b, out result);
```

Use the out-parameter form in hot paths.

### CRepr Attribute

Vector3 and Vector4 use `[CRepr]` for C-compatible memory layout, enabling direct GPU buffer uploads.

## Best Practices

1. **Use squared distances** when comparing - avoid sqrt
2. **Prefer out parameters** in hot loops
3. **Normalize quaternions** after multiple operations
4. **Use SmoothStep** for smooth animations
5. **Check frustum containment** for culling before rendering
6. **Cache transform matrices** when possible

## Project Structure

```
Code/Sedulous/Sedulous.Mathematics/src/
├── Vector2.bf, Vector3.bf, Vector4.bf
├── Point2.bf, Point2F.bf, Point2D.bf
├── Size2.bf, Size2F.bf, Size2D.bf
├── Size3.bf, Size3F.bf, Size3D.bf
├── Rectangle.bf, RectangleF.bf, RectangleD.bf
├── Circle.bf, CircleF.bf, CircleD.bf
├── Matrix.bf
├── Quaternion.bf
├── Radians.bf
├── Plane.bf
├── Ray.bf
├── BoundingBox.bf
├── BoundingSphere.bf
├── BoundingFrustum.bf
├── Color.bf
├── MathUtil.bf
├── ContainmentType.bf
├── PlaneIntersectionType.bf
└── IInterpolatable.bf
```
