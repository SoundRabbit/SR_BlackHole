Shader "SoundRabbit/GravitationalLens"
{
    Properties {
        [MainColor]
        _Color ("Color of Black Hole", Color) = (0, 0, 0, 1)
        _PhotonRingColor ("Color of Photon Ring", Color) = (1, 1, 0.5, 1)

        _Rad ("Radius", Float) = 0.5
        _Ord ("Order", Float) = 1.0
        _Bas ("Base", Float) = 2.0
        _Cor ("カットオフ距離", Float) = 1.01

        _UseExpo ("Use Exponential", Float) = 0
        _CalcRadInFrag("Calculate Radius in Fragment Shader", Float) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Transparent+1000" "RenderType" = "Opaque" "VRCFallback" = "Unlit" }

        CGINCLUDE
        ENDCG

        GrabPass {}

        Pass
        {
            Cull Front

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ USE_EXPO
            #pragma multi_compile _ CALC_RAD_IN_FRAG

            #include "UnityCG.cginc"

            #define PI 3.1415926535897932384626433832795

            float4 _Color;
            float4 _PhotonRingColor;

            float _Rad;
            float _Ord;
            float _Bas;
            float _Cor;
            
            float _UseExpo;
            float _CalcRadInFrag;

            sampler2D _GrabTexture;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 grabPos : TEXCOORD0;
                float4 pos : SV_POSITION;
                float3 p: POSITION1;
                float aspect: Any0;

                float r: Any1;

                float3 viewPos: POSITION2;
                float3 viewOriginPos: POSITION3;
            };

            v2f vert (appdata v)
            {
                v2f o;

                // ビルボードとしてクリップ空間での位置を計算
                float3 viewOriginPos = UnityObjectToViewPos(float4(0, 0, 0, 1));
                float3 scaleRotatePos = mul((float3x3)unity_ObjectToWorld, v.vertex);
                float3 viewPos = viewOriginPos + float3(scaleRotatePos.xy, -scaleRotatePos.z);
                o.pos = mul(UNITY_MATRIX_P, float4(viewPos, 1));

                // GrabPassの座標を計算
                o.grabPos = ComputeGrabScreenPos(o.pos);

                // スクリーン上での中心からのずれを計算
                float4 pOrigin = UnityObjectToClipPos(float4(0, 0, 0, 1));
                o.p = o.pos.xyz / o.pos.w - pOrigin.xyz / pOrigin.w;
                o.p.y *= -1;

                // カメラアスペクト比を計算
                float4 projectionSpaceUpperRight = float4(1, 1, UNITY_NEAR_CLIP_VALUE, _ProjectionParams.y);
                float4 viewSpaceUpperRight = mul(unity_CameraInvProjection, projectionSpaceUpperRight);
                o.aspect = viewSpaceUpperRight.x / viewSpaceUpperRight.y;

                // 中心からの距離を計算
                #ifdef CALC_RAD_IN_FRAG
                    o.viewPos = viewPos;
                    o.viewOriginPos = viewOriginPos;
                #else
                    float r1 = unity_OrthoParams[3] == 1 ?
                        length(viewPos.xy - viewOriginPos.xy) :
                        length(cross(viewOriginPos, viewPos)) / length(viewOriginPos);
                    float r2 = length(viewPos - viewOriginPos);
                    o.r = r2 == 0 ? 0 : clamp(r1 / r2, 0, 1);
                #endif

                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 中心からの距離を計算
                float ir;
                #ifdef CALC_RAD_IN_FRAG
                    float r1 = unity_OrthoParams[3] == 1 ?
                        length(i.viewPos.xy - i.viewOriginPos.xy) :
                        length(cross(i.viewOriginPos, i.viewPos)) / length(i.viewOriginPos);
                    float r2 = length(i.viewPos - i.viewOriginPos);
                    ir = r2 == 0 ? 0 : clamp(r1 / r2, 0, 1);
                #else
                    ir = i.r;
                #endif

                // 屈折角を計算（カメラには平行光として入ると仮定）
                #ifdef USE_EXPO
                    ir = clamp((pow(_Bas, ir) - 1) / (_Bas - 1), 0, 1);
                    float ra = clamp((pow(_Bas, _Rad) - 1) / (_Bas - 1), 0, 1);
                    float rt = (PI * ra) / (2 - 2 * ra);
                #else
                    ir = pow(ir, _Ord);
                    float ra = pow(_Rad, _Ord);
                    float rt = (PI * ra) / (2 - 2 * ra);
                #endif
                float refractionAngle = max(0, rt / ir - rt * _Cor);
                float refractionDist = tan(refractionAngle);
                float2 offsetDir = refractionDist * normalize(i.p.xy);

                // GrabPassの座標をずらす
                float4 grabPos = i.grabPos;
                grabPos.x -= offsetDir.x / i.aspect * grabPos.w;
                grabPos.y -= offsetDir.y * grabPos.w;

                //光子球の色を計算
                refractionDist = abs(refractionDist);
                float4 photonRingColor =
                    float4(refractionDist, refractionDist, refractionDist, 1)
                    * _PhotonRingColor;
                photonRingColor.r = max(1.0, photonRingColor.r);
                photonRingColor.g = max(1.0, photonRingColor.g);
                photonRingColor.b = max(1.0, photonRingColor.b);
                photonRingColor.a = max(1.0, photonRingColor.a);

                // 色を計算
                half4 bgcolor =
                    refractionAngle > PI / 2 ?
                        _Color :
                        tex2Dproj(_GrabTexture , grabPos) * photonRingColor;
                        
                return bgcolor;
            }
            ENDCG
        }
    }

    CustomEditor "SR_BlackHole.ShaderEditor"
}
