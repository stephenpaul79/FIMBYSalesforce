function openModal(modalId) {
    var modal = document.getElementById(modalId);
    modal.style.display = "block";
    var modalImg = modal.querySelector(".modal-content");
    modalImg.src = event.target.src; // Sets the source to the clicked image
}

function closeModal(modalId) {
    var modal = document.getElementById(modalId);
    modal.style.display = "none";
}