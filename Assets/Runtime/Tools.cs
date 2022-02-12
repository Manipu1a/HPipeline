using System.Numerics;
using Matrix4x4 = UnityEngine.Matrix4x4;
using Vector3 = UnityEngine.Vector3;
using Vector4 = UnityEngine.Vector4;

public class Tools
{
    public static Matrix4x4 LookAt(Vector3 Eye, Vector3 Center, Vector3 Up)
    {
        //Z向量指向foward
        Vector3 Z = Vector3.Normalize( Center - Eye);
        //Y指向up
        Vector3 Y = Up;
        //X指向right
        Vector3 X = Vector3.Cross(Y, Z);
        X = Vector3.Normalize(X);
        Y = Vector3.Cross(Z,X);
        Y = Vector3.Normalize(Y);

        Matrix4x4 matrix = new Matrix4x4();
        matrix.SetColumn(0, new Vector4(X.x, X.y, X.z,0.0f));
        matrix.SetColumn(1, new Vector4(Y.x, Y.y, Y.z,0.0f));
        matrix.SetColumn(2, new Vector4(Z.x, Z.y, Z.z,0.0f));
        matrix.SetColumn(3, new Vector4(-Vector3.Dot(X, Eye), -Vector3.Dot(Y, Eye), -Vector3.Dot(Z, Eye),1.0f));

        return matrix;
    }
    
    //保存rt到图片中
    
}
