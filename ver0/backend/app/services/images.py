"""이미지 유틸: 저장용 재인코딩 + LLM 전송용 리사이즈.

원본을 그대로 LLM에 보내면 vision 토큰 비용이 크게 늘어난다.
1024px 이하 JPEG로 압축해도 회고 질문 품질에는 차이가 없다.
"""
import io

from PIL import Image, ImageOps

from ..config import get_settings


def reencode_for_storage(data: bytes) -> bytes:
    """업로드 원본 → 서버 저장본 JPEG (개발 PRD 8장 보안·개인정보).

    Pillow 재인코딩으로 EXIF(GPS 위치 포함) 메타데이터를 서버 저장 전에 제거하고,
    photo_max_side_storage 이하로 리사이즈한다. 회전 정보는 픽셀에 미리 반영.
    디코딩 불가능한 형식(pillow-heif 미설치 시 HEIC 등)은 예외를 던진다.
    """
    settings = get_settings()
    max_side = settings.photo_max_side_storage

    with Image.open(io.BytesIO(data)) as img:
        img = ImageOps.exif_transpose(img)
        img = img.convert("RGB")
        img.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=90)  # exif 미전달 → 메타데이터 제거됨
        return buf.getvalue()


def resize_for_ai(file_path: str) -> bytes:
    settings = get_settings()
    max_side = settings.photo_max_side_for_ai

    with Image.open(file_path) as img:
        img = ImageOps.exif_transpose(img)  # 회전 정보 반영
        img = img.convert("RGB")
        img.thumbnail((max_side, max_side))
        buf = io.BytesIO()
        img.save(buf, format="JPEG", quality=85)
        return buf.getvalue()
