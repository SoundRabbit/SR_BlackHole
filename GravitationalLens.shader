Shader "SoundRabbit/Gravity"
{
    Properties {
        _Rt ("距離倍率（逆数）", Float) = 1.0
        _Od ("距離次数", Float) = 1.0
        _Co ("カットオフ距離", Float) = 1.01
    }

    SubShader
    {
        Tags { "Queue" = "Transparent+1000" "RenderType" = "Opaque" }

        GrabPass
        {
            "_GrabPassTexture"
        }

        LOD 100

        Pass
        {
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            #define PI 3.1415926535897932384626433832795

            float _Rt;
            float _Od;
            float _Co;

            sampler2D _GrabPassTexture;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 grabPos : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 p: Any0;
                float3 vertex: Any1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.grabPos = ComputeGrabScreenPos(o.pos);
                o.vertex = v.vertex;

                float4 pOrigin = UnityObjectToClipPos(float4(0, 0, 0, 1));
                o.p = o.pos.xyz / o.pos.w - pOrigin.xyz / pOrigin.w;
                o.p.y *= -1;

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 projectionSpaceUpperRight = float4(1, 1, UNITY_NEAR_CLIP_VALUE, _ProjectionParams.y);
                float4 viewSpaceUpperRight = mul(unity_CameraInvProjection, projectionSpaceUpperRight);
                float aspect = viewSpaceUpperRight.x / viewSpaceUpperRight.y;

                float3 rOrigin = UnityObjectToViewPos(float4(0, 0, 0, 1));
                float3 rVertex = UnityObjectToViewPos(i.vertex);
                float r1 = length(cross(rVertex, rOrigin)) / length(rOrigin);
                float r2 = length(rVertex - rOrigin);
                float r = r1 / r2;
                float rInv = 1 / r;

                float4 grabPos = i.grabPos;
                float offsetRad = max(0, pow(rInv, _Od) * _Rt - _Rt * _Co);
                float2 offsetDir = tan(offsetRad) * normalize(i.p.xy);

                grabPos.x -= offsetDir.x / aspect * grabPos.w;
                grabPos.y -= offsetDir.y * grabPos.w;

                half4 bgcolor =
                    offsetRad > PI / 2 ?
                        half4(0, 0, 0, 1) :
                        tex2Dproj(_GrabPassTexture, grabPos);
                        
                return bgcolor;
            }
            ENDCG
        }
    }
}
