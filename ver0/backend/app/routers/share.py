"""[FUTURE — 현재 PRD 범위 밖, 확장 대비 선구현]
필름 공유 링크 (서비스 PRD 14장 확장 기능 "결과물 공유").

현재 MVP 의 공유는 프론트가 필름 카드를 PNG 로 저장해 공유하는 방식이라
이 라우터 없이도 서비스는 완결된다. 웹 링크 공유(카카오톡 미리보기,
인스타 스토리 링크 등)를 도입할 때 이 API 를 프론트에 연결하면 된다.

절대 원칙 (개발 PRD 8장): 공유 응답에는 대화 원문·기억 포인트(키워드)·
위치 정보를 포함하지 않는다. SharedFilmOut 에 필드를 추가하기 전에
반드시 공개 가능 여부를 검토할 것.
"""
import secrets
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import DailyFilmRecord, ShareLink, User
from ..schemas import ShareLinkOut, SharedFilmOut

router = APIRouter(tags=["share"])


def _active_link(db: Session, record_id: str) -> ShareLink | None:
    return db.scalar(
        select(ShareLink).where(ShareLink.record_id == record_id, ShareLink.revoked.is_(False))
    )


@router.post("/records/{record_id}/share", response_model=ShareLinkOut, status_code=201)
def create_share_link(record_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    record = db.get(DailyFilmRecord, record_id)
    if record is None or record.user_id != user.id:
        raise HTTPException(404, "기록을 찾을 수 없어요.")
    if record.status != "completed":
        raise HTTPException(400, "완성된 필름만 공유할 수 있어요.")

    link = _active_link(db, record.id)
    if link is None:
        link = ShareLink(
            token=secrets.token_urlsafe(16),  # 추측 불가능한 공개 토큰
            user_id=user.id,
            record_id=record.id,
        )
        db.add(link)
        db.commit()
        db.refresh(link)
    return ShareLinkOut(token=link.token, url=f"/share/{link.token}")


@router.delete("/records/{record_id}/share", status_code=204)
def revoke_share_link(record_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    record = db.get(DailyFilmRecord, record_id)
    if record is None or record.user_id != user.id:
        raise HTTPException(404, "기록을 찾을 수 없어요.")
    link = _active_link(db, record.id)
    if link:
        link.revoked = True
        db.commit()


def _get_shared_record(token: str, db: Session) -> tuple[ShareLink, DailyFilmRecord]:
    link = db.scalar(select(ShareLink).where(ShareLink.token == token, ShareLink.revoked.is_(False)))
    record = db.get(DailyFilmRecord, link.record_id) if link else None
    if link is None or record is None:
        raise HTTPException(404, "존재하지 않거나 만료된 공유 링크예요.")
    return link, record


@router.get("/share/{token}", response_model=SharedFilmOut)
def view_shared_film(token: str, db: Session = Depends(get_db)):
    """공개 조회 (무인증). 대화·키워드·위치는 스키마 차원에서 제외되어 있다."""
    link, record = _get_shared_record(token, db)
    owner = db.get(User, link.user_id)
    main = next((p for p in record.photos if p.is_main), record.photos[0] if record.photos else None)
    return SharedFilmOut(
        date=record.date,
        film_title=record.film_title,
        ending_narration=record.ending_narration,
        representative_sentence=record.representative_sentence,
        nickname=owner.nickname if owner else "",
        photo_url=f"/share/{token}/photo" if main else None,
    )


@router.get("/share/{token}/photo")
def shared_photo(token: str, db: Session = Depends(get_db)):
    """공유된 필름의 대표 사진 (무인증 — 링크 소유가 곧 열람 권한)."""
    _, record = _get_shared_record(token, db)
    main = next((p for p in record.photos if p.is_main), record.photos[0] if record.photos else None)
    if main is None or not Path(main.file_path).is_file():
        raise HTTPException(404, "사진을 찾을 수 없어요.")
    return FileResponse(main.file_path, headers={"Cache-Control": "public, max-age=3600"})
