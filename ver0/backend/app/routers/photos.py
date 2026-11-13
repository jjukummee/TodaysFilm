"""사진 업로드 + 인증된 사진 서빙.

사진은 사적 데이터다. 정적 서빙(/uploads) 대신 소유자 검증을 거치는
GET /photos/{id}/file 로만 접근할 수 있다.
[운영 확장] 트래픽이 커지면 S3/Supabase Storage + presigned URL로 교체
— 이 파일의 저장/서빙 부분만 바꾸면 된다.
"""
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..config import get_settings
from ..database import get_db
from ..deps import get_current_user
from ..models import Photo, User
from ..schemas import PhotoOut
from ..services import images

router = APIRouter(prefix="/photos", tags=["photos"])

ALLOWED = {"image/jpeg", "image/png", "image/webp", "image/heic"}
# 용량 제한은 .env 의 PHOTO_MAX_UPLOAD_MB 로 조정 (기본 40MB — 고화질 원본 대응)
# 참고: LLM에는 어차피 1024px 리사이즈본만 전송되므로 원본이 커도 AI 비용은 동일하다.
# 주의: HEIC 는 pillow-heif 설치 시에만 실제 디코딩 가능 (미설치면 아래 재인코딩에서 400)


def photo_url(photo: Photo) -> str:
    """클라이언트에 내려주는 사진 접근 URL (인증 필요)."""
    return f"/photos/{photo.id}/file"


@router.post("/upload", response_model=list[PhotoOut], status_code=201)
async def upload_photos(
    files: list[UploadFile] = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not 1 <= len(files) <= 5:  # PRD 7.1: 1~5장
        raise HTTPException(400, "사진은 1~5장까지 업로드할 수 있어요.")

    settings = get_settings()
    max_size = settings.photo_max_upload_mb * 1024 * 1024
    upload_dir = Path(settings.upload_dir) / user.id
    upload_dir.mkdir(parents=True, exist_ok=True)

    out = []
    for f in files:
        if f.content_type not in ALLOWED:
            raise HTTPException(400, f"지원하지 않는 형식이에요: {f.content_type}")
        data = await f.read()
        if len(data) > max_size:
            raise HTTPException(400, f"사진 용량은 {settings.photo_max_upload_mb}MB 이하여야 해요.")

        # 개발 PRD 8장: EXIF(GPS) 제거 + 리사이즈 재인코딩 후에만 저장
        try:
            data = images.reencode_for_storage(data)
        except Exception:
            raise HTTPException(400, "이미지를 처리할 수 없어요. JPEG/PNG/WebP 형식인지 확인해 주세요.")

        path = upload_dir / f"{uuid.uuid4().hex}.jpg"
        path.write_bytes(data)

        photo = Photo(user_id=user.id, file_path=str(path))
        db.add(photo)
        db.flush()
        out.append(PhotoOut(id=photo.id, url=photo_url(photo), is_main=False))

    db.commit()
    return out


@router.get("/{photo_id}/file")
def get_photo_file(
    photo_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """사진 파일 서빙 — 소유자만 접근 가능."""
    photo = db.get(Photo, photo_id)
    if photo is None or photo.user_id != user.id:
        raise HTTPException(404, "사진을 찾을 수 없어요.")
    path = Path(photo.file_path)
    if not path.is_file():
        raise HTTPException(404, "사진 파일이 존재하지 않아요.")
    return FileResponse(
        path,
        headers={"Cache-Control": "private, max-age=86400"},  # 개인 캐시만 허용
    )
